# frozen_string_literal: true

RSpec.describe PgEventstore::Callbacks do
  let(:instance) { described_class.new }

  describe '#define_callback' do
    subject { instance.define_callback(action, filter, callback) }

    let(:action) { :my_action }
    let(:filter) { :before }
    let(:callback) { proc { } }
    let(:callbacks) { instance.instance_variable_get(:@callbacks) }

    it 'memorizes it' do
      expect { subject }.to change { callbacks }.to(action => { filter => [callback] })
    end
  end

  describe '#run_callbacks' do
    subject { instance.run_callbacks(action, &block) }

    let(:action) { :my_action }
    let(:block) { proc { call_once_object.result } }
    let(:call_once_object) { double }

    before do
      allow(call_once_object).to receive(:result).and_return(:some_block_result)
    end

    context 'when no callbacks are registered for the given action' do
      context 'when no block is given' do
        subject { instance.run_callbacks(action) }

        it { is_expected.to be_nil}
      end

      context 'when block is given' do
        it 'returns the result of the given block' do
          is_expected.to eq(:some_block_result)
        end
        it 'calls the block exactly once' do
          subject
          expect(call_once_object).to have_received(:result).once
        end
      end
    end

    context 'when there are registered callbacks' do
      let(:call_stack) { [] }
      let(:before_callback1) { proc { call_stack.push(:before_1) } }
      let(:before_callback2) { proc { call_stack.push(:before_2) } }
      let(:around_callback1) do
        proc do |action|
          call_stack.push(:around_1_before)
          action.call
          call_stack.push(:around_1_after)
        end
      end
      let(:around_callback2) do
        proc do |action|
          call_stack.push(:around_2_before)
          action.call
          call_stack.push(:around_2_after)
        end
      end
      let(:after_callback1) { proc { call_stack.push(:after_1) } }
      let(:after_callback2) { proc { call_stack.push(:after_2) } }

      before do
        instance.define_callback(action, :before, before_callback1)
        instance.define_callback(action, :before, before_callback2)
        instance.define_callback(action, :around, around_callback1)
        instance.define_callback(action, :around, around_callback2)
        instance.define_callback(action, :after, after_callback1)
        instance.define_callback(action, :after, after_callback2)
        # Register the callback for another action to ensure different actions callbacks don't leak into each other
        instance.define_callback(:some_another_action, :after, after_callback1)
      end

      shared_examples 'callbacks execution' do
        it 'executes callbacks in the correct order' do
          subject
          expect(call_stack).to(
            eq(%i[before_1 before_2 around_1_before around_2_before around_2_after around_1_after after_1 after_2])
          )
        end
      end

      context 'when no block is given' do
        subject { instance.run_callbacks(action) }

        it { is_expected.to be_nil }
        it_behaves_like 'callbacks execution'
      end

      context 'when block is given' do
        it 'returns the result of the given block' do
          is_expected.to eq(:some_block_result)
        end
        it_behaves_like 'callbacks execution'
        it 'calls the block exactly once' do
          subject
          expect(call_once_object).to have_received(:result).once
        end
      end
    end

    describe 'additional arguments' do
      let(:called_args) { {} }
      let(:before_callback) { proc { |*args, **kwargs, &blk| called_args[:before] = [args, kwargs, blk] } }
      let(:around_callback) do
        proc do |action, *args, **kwargs, &blk|
          called_args[:around] = [args, kwargs, blk]
          action.call
        end
      end
      let(:after_callback) { proc { |*args, **kwargs, &blk| called_args[:after] = [args, kwargs, blk] } }

      before do
        instance.define_callback(action, :before, before_callback)
        instance.define_callback(action, :around, around_callback)
        instance.define_callback(action, :after, after_callback)
      end

      context 'when no additional arguments are provided' do
        it 'does not pass any arguments into any of the registered callbacks' do
          subject
          expect(called_args).to(
            eq(before: [[], {}, nil], around: [[], {}, nil], after: [[], {}, nil])
          )
        end
      end

      context 'when additional arguments are provided' do
        subject { instance.run_callbacks(action, :foo, bar: :baz, &block) }

        it 'bypasses those arguments into each registered callback' do
          subject
          expect(called_args).to(
            eq(
              before: [[:foo], { bar: :baz }, nil],
              around: [[:foo], { bar: :baz }, nil],
              after: [[:foo], { bar: :baz }, nil]
            )
          )
        end
      end
    end
  end
end

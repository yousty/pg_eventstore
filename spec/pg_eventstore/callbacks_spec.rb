# frozen_string_literal: true

RSpec.describe PgEventstore::Callbacks do
  let(:instance) { described_class.new }

  describe '#define_callback' do
    subject { instance.define_callback(action, filter, callback) }

    let(:action) { :my_action }
    let(:filter) { :before }
    let(:callback) { proc {} }
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

        it { is_expected.to be_nil }
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
      let(:before_callback1) { proc { call_stack.push(:before1) } }
      let(:before_callback2) { proc { call_stack.push(:before2) } }
      let(:around_callback1) do
        proc do |action|
          call_stack.push(:around1_before)
          action.call
          call_stack.push(:around1_after)
        end
      end
      let(:around_callback2) do
        proc do |action|
          call_stack.push(:around2_before)
          action.call
          call_stack.push(:around2_after)
        end
      end
      let(:after_callback1) { proc { call_stack.push(:after1) } }
      let(:after_callback2) { proc { call_stack.push(:after2) } }

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
            eq(%i[before1 before2 around1_before around2_before around2_after around1_after after1 after2])
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

  describe '#remove_callback' do
    subject { instance.remove_callback(action, filter, callback) }

    let(:action) { :my_action }
    let(:another_action) { :foo_action }
    let(:filter) { :before }
    let(:another_filter) { :after }
    let(:callback) { proc {} }
    let(:callbacks) { instance.instance_variable_get(:@callbacks) }

    before do
      instance.define_callback(action, filter, callback)
      instance.define_callback(action, another_filter, callback)
      instance.define_callback(another_action, filter, callback)
    end

    it 'removes the given callback from callbacks list by the given filter and action' do
      expect { subject }.to change { callbacks.dig(action, filter) }.from([callback]).to([])
    end
    it 'does not remove the given callback for unaffected filter' do
      expect { subject }.not_to change { callbacks.dig(action, another_filter) }.from([callback])
    end
    it 'does not remove the given callback for unaffected action' do
      expect { subject }.not_to change { callbacks.dig(another_action, filter) }.from([callback])
    end
  end

  describe '#clear' do
    subject { instance.clear }

    let(:callbacks) { instance.instance_variable_get(:@callbacks) }

    before do
      instance.define_callback(:my_action, :before, proc {})
    end

    it 'clears defined callbacks' do
      expect { subject }.to change { callbacks }.from(a_hash_including(:my_action)).to({})
    end
  end
end

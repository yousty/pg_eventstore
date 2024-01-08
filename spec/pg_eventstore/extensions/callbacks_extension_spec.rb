# frozen_string_literal: true

RSpec.describe PgEventstore::Extensions::CallbacksExtension do
  let(:dummy_class) do
    Class.new.tap do |klass|
      klass.include described_class
    end
  end
  let(:dummy_instance) { dummy_class.new }

  describe '.has_callbacks' do
    subject { dummy_class.has_callbacks(:my_action, method_to_wrap) }

    let(:call_stack) { [] }
    let(:method_to_wrap) { :some_method }

    before do
      call_stack = self.call_stack
      dummy_class.define_method(method_to_wrap) { call_stack.push(:method_call); :the_result }
      dummy_instance.define_callback(:my_action, :before, proc { call_stack.push(:before) })
      dummy_instance.define_callback(
        :my_action, :around,
        proc do |action|
          call_stack.push(:around_before)
          action.call
          call_stack.push(:around_after)
        end
      )
      dummy_instance.define_callback(:my_action, :after, proc { call_stack.push(:after) })
    end

    shared_examples 'wrapping the given method' do
      it 'wraps the given method into run_callbacks' do
        subject
        aggregate_failures do
          expect(dummy_instance.send(method_to_wrap)).to eq(:the_result)
          expect(call_stack).to(
            eq(%i[before around_before method_call around_after after])
          )
        end
      end
    end

    context 'when method is public' do
      it_behaves_like 'wrapping the given method'
    end

    context 'when method is protected' do
      before do
        dummy_class.send(:protected, method_to_wrap)
      end

      it 'keeps its visibility' do
        subject
        expect(dummy_instance.protected_methods).to include(method_to_wrap)
      end
      it_behaves_like 'wrapping the given method'
    end

    context 'when method is private' do
      before do
        dummy_class.send(:private, method_to_wrap)
      end

      it 'keeps its visibility' do
        subject
        expect(dummy_instance.private_methods).to include(method_to_wrap)
      end
      it_behaves_like 'wrapping the given method'
    end
  end
end

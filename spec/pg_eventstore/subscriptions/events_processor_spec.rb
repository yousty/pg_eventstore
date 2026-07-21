# frozen_string_literal: true

RSpec.describe PgEventstore::EventsProcessor do
  let(:instance) { described_class.new(consumer:, graceful_shutdown_timeout:, events_repository:) }
  let(:handler) { proc { |raw_event| processed_events.push(raw_event['global_position']) } }
  let(:consumer) { PgEventstore::EventsProcessorConsumer::Single.new(handler) }
  let(:events_repository) { PgEventstore::Chunks::Repository.new }
  let(:graceful_shutdown_timeout) { 5 }
  let(:processed_events) { [] }

  describe 'instance' do
    subject { instance }

    it { is_expected.to be_a(PgEventstore::Extensions::CallbacksExtension) }
  end

  describe '#feed' do
    subject { instance.feed(chunk) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:event1) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
    let(:event2) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
    let(:event3) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
    let(:event4) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }

    let(:indexes) { prepare_subscription_indexes([event1, event2]) }
    let(:indexes_in_queue) { prepare_subscription_indexes([event3, event4]) }

    let(:chunk) { create_subscription_index_chunk(indexes) }
    let(:chunk_in_queue) { create_subscription_index_chunk(indexes_in_queue) }

    let(:feed_callback) { proc { |pos| subscription_position_receiver.call(pos) } }
    let(:subscription_position_receiver) { double('Global position receiver') }
    let(:handler) { proc { |raw_event| sleep 0.5; processed_events.push(raw_event['id']) } }

    before do
      instance.start
      # give runner time to try to consume first event and then get into sleep, so we can test changes in the chunk
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      instance.feed(chunk_in_queue)
      dv(processed_events).wait_until(timeout: 0.1) { !_1.empty? }
      allow(subscription_position_receiver).to receive(:call)
      instance.define_callback(:feed, :after, feed_callback)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    context 'when runner is running' do
      it 'adds the given event indexes to the queue' do
        expect { subject }.to change { instance.instance_variable_get(:@events_repository).size }.by(2)
      end
      it 'executes :feed action' do
        subject
        expect(subscription_position_receiver).to have_received(:call).with(indexes.last.subscription_position)
      end

      context 'when empty chunk is fed' do
        let(:chunk) { create_subscription_index_chunk([]) }

        it 'raises error' do
          expect { subject }.to raise_error(PgEventstore::EmptyChunkFedError)
        end
        it 'does not change the queue' do
          expect { subject rescue nil }.not_to change {
            instance.instance_variable_get(:@events_repository).size
          }.from(1)
        end
        it 'does not execute :feed action' do
          subject rescue nil
          expect(subscription_position_receiver).not_to have_received(:call).with(nil)
        end
      end
    end

    context 'when runner is not in the :running state' do
      before do
        instance.stop_async.wait_for_finish
      end

      it 'does not change the queue' do
        expect { subject }.not_to change { instance.instance_variable_get(:@events_repository).size }
      end
      it 'does not execute :feed action' do
        subject
        expect(subscription_position_receiver).not_to have_received(:call).with(nil)
      end
    end
  end

  describe '#events_left_in_repo' do
    subject { instance.events_left_in_repo }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:event1) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
    let(:event2) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
    let(:indexes) { prepare_subscription_indexes([event1, event2]) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

    before do
      instance.start
      # give runner time to try to consume first event and then get into sleep, so we can test changes in the chunk
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      instance.feed(chunk)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'returns events repository size' do
      is_expected.to eq(2)
    end
  end

  describe '#clear_events_repository' do
    subject { instance.clear_events_repository }

    let(:handler) do
      should_raise = true
      proc do |raw_event|
        if should_raise
          should_raise = false
          raise 'Oops!'
        end
        processed_events.push(raw_event)
      end
    end
    let(:synchronizer) { Thread::Queue.new }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(5) { PgEventstore::Event.new }) }
    let(:indexes) { prepare_subscription_indexes(events) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

    before do
      instance.start
      # give runner time to try to consume first event and then get into sleep, so we can test changes in the chunk
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      instance.feed(chunk)
      dv(instance).wait_until(timeout: 0.2) { _1.state == 'dead' }
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'clears events repo' do
      expect { subject }.to change { instance.events_left_in_repo }.from(4).to(0)
    end
    it 'clears unprocessed events' do
      subject
      restore = proc do
        instance.restore
        dv(instance).wait_until(timeout: 0.2) { _1.state == 'running' }
        sleep 0.1
      end
      expect(&restore).not_to change { processed_events }
    end
  end

  describe 'async action' do
    subject { instance.feed(chunk) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new }) }
    let(:indexes) { prepare_subscription_indexes(events) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

    before do
      instance.start
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'processes the given events' do
      expect { subject }.to change {
        dv(processed_events).deferred_wait(timeout: 0.6) { _1.size == events.size }
      }.to(events.map(&:global_position))
    end
  end

  describe "on runner's death" do
    subject { instance.start }

    let(:on_error_cbx) { proc { |error| error_receiver.call(error) } }
    let(:error_receiver) { double('Error receiver') }
    let(:error) { StandardError.new('Oops!') }
    let(:handler) do
      proc { sleep 0.2; raise error }
    end

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, [PgEventstore::Event.new]) }
    let(:indexes) { prepare_subscription_indexes(events) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

    before do
      instance.define_callback(:error, :after, on_error_cbx)
      allow(error_receiver).to receive(:call)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'runs :error action' do
      subject
      # Let the runner start and die
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'dead' }
      # Feed the processor to trigger the error
      instance.feed(chunk)
      aggregate_failures do
        expect(error_receiver).not_to have_received(:call)
        sleep 0.5
        # After half a second we perform the same test over the same object, but with different expectation to prove
        # that the action is actually asynchronous
        expect(error_receiver).to have_received(:call).with(instance_of(PgEventstore::WrappedException))
      end
    end
  end

  describe 'on restart' do
    subject { instance.restore }

    let(:on_restart_cbx) { proc { restart_receiver.call } }
    let(:restart_receiver) { double('Restart receiver') }
    let(:handler) do
      proc { raise 'Oops!' }
    end

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, [PgEventstore::Event.new]) }
    let(:indexes) { prepare_subscription_indexes(events) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

    before do
      instance.define_callback(:restart, :after, on_restart_cbx)
      allow(restart_receiver).to receive(:call)
      instance.start
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'runs :restart action' do
      # Feed the processor to trigger the error
      instance.feed(chunk)
      # Let the runner time to die
      dv(instance).wait_until(timeout: 0.6) { _1.state == 'dead' }
      subject
      expect(restart_receiver).to have_received(:call)
    end
  end

  describe 'on state change' do
    subject { instance.start }

    let(:on_state_change_cbx) { proc { |state| state_change_receiver.call(state) } }
    let(:state_change_receiver) { double('State change receiver') }

    before do
      allow(state_change_receiver).to receive(:call)
      instance.define_callback(:change_state, :after, on_state_change_cbx)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'runs :change_state action' do
      subject
      expect(state_change_receiver).to have_received(:call).with('running')
    end
  end

  describe 'on async action processed' do
    subject { instance.start }

    let(:on_process_cbx) { proc { |pos| subscription_position_receiver.call(pos) } }
    let(:subscription_position_receiver) { double('Subscription position receiver') }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new }) }
    let(:indexes) { prepare_subscription_indexes(events) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

    before do
      allow(subscription_position_receiver).to receive(:call)
      instance.define_callback(:process, :after, on_process_cbx)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'runs :process action' do
      subject
      #  Let the runner start
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      aggregate_failures do
        expect(subscription_position_receiver).not_to have_received(:call)
        # Feed the processor to trigger the event processing
        instance.feed(chunk)
        # Let the runner to process the given events
        dv(processed_events).wait_until(timeout: 0.6) { _1.size == events.size }
        # After half a second we perform the same test over the same object, but with different expectation to prove
        # that the action is actually asynchronous
        expect(subscription_position_receiver).to have_received(:call).with(indexes.first.subscription_position)
        expect(subscription_position_receiver).to have_received(:call).with(indexes.last.subscription_position)
      end
    end
  end
end

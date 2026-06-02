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
    subject { instance.feed(EventIndexesChunk.create_indexes(raw_indexes)) }

    let(:raw_indexes) { [event_index1, event_index2] }
    let(:event_index1) { { 'global_position' => 3, 'event_type_partition_id' => 2 } }
    let(:event_index2) { { 'global_position' => 4, 'event_type_partition_id' => 2 } }
    let(:event_index_in_queue1) { { 'global_position' => 1, 'event_type_partition_id' => 3 } }
    let(:event_index_in_queue2) { { 'global_position' => 2, 'event_type_partition_id' => 3 } }
    let(:feed_callback) { proc { |latest_global_position| global_position_receiver.call(latest_global_position) } }
    let(:global_position_receiver) { double('Global position receiver') }
    let(:handler) { proc { |raw_event| sleep 0.5; processed_events.push(raw_event['id']) } }

    before do
      instance.start
      # give runner time to try to consume first event and then get into sleep, so we can test changes in the chunk
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      instance.feed(EventIndexesChunk.create_indexes([event_index_in_queue1, event_index_in_queue2]))
      dv(processed_events).wait_until(timeout: 0.1) { !_1.empty? }
      allow(global_position_receiver).to receive(:call)
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
        expect(global_position_receiver).to have_received(:call).with(4)
      end

      context 'when no event indexes are fed' do
        let(:raw_indexes) { [] }

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
          expect(global_position_receiver).not_to have_received(:call).with(nil)
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
        expect(global_position_receiver).not_to have_received(:call).with(nil)
      end
    end
  end

  describe '#events_left_in_repo' do
    subject { instance.events_left_in_repo }

    before do
      instance.start
      # give runner time to try to consume first event and then get into sleep, so we can test changes in the chunk
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      instance.feed(
        EventIndexesChunk.create_indexes(
          [
            { 'global_position' => 1, 'event_type_partition_id' => 2 },
            { 'global_position' => 2, 'event_type_partition_id' => 2 },
          ]
        )
      )
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

    before do
      instance.start
      # give runner time to try to consume first event and then get into sleep, so we can test changes in the chunk
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      instance.feed(
        EventIndexesChunk.create_indexes(
          Array.new(5) { |i| { 'global_position' => i, 'event_type_partition_id' => 2 } }
        )
      )
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
    subject { instance.feed(EventIndexesChunk.create_indexes(raw_indexes)) }

    let(:raw_indexes) do
      [
        { 'global_position' => 123, 'event_type_partition_id' => 2 },
        { 'global_position' => 124, 'event_type_partition_id' => 2 },
      ]
    end

    before do
      instance.start
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'processes the given events' do
      expect { subject }.to change {
        dv(processed_events).deferred_wait(timeout: 0.6) { _1.size == raw_indexes.size }
      }.to(raw_indexes.map { _1['global_position'] })
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
      instance.feed(EventIndexesChunk.create_indexes([{ 'global_position' => 1, 'event_type_partition_id' => 2 }]))
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
      instance.feed(EventIndexesChunk.create_indexes([ 'global_position' => 1, 'event_type_partition_id' => 2 ]))
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

    let(:on_process_cbx) { proc { |global_position| global_position_receiver.call(global_position) } }
    let(:global_position_receiver) { double('Global position receiver') }
    let(:raw_indexes) do
      [
        { 'global_position' => 123, 'event_type_partition_id' => 2 },
        { 'global_position' => 124, 'event_type_partition_id' => 2 },
      ]
    end

    before do
      allow(global_position_receiver).to receive(:call)
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
        expect(global_position_receiver).not_to have_received(:call)
        # Feed the processor to trigger the event processing
        instance.feed(EventIndexesChunk.create_indexes(raw_indexes))
        # Let the runner to process the given events
        dv(processed_events).wait_until(timeout: 0.6) { _1.size == raw_indexes.size }
        # After half a second we perform the same test over the same object, but with different expectation to prove
        # that the action is actually asynchronous
        expect(global_position_receiver).to have_received(:call).with(123)
        expect(global_position_receiver).to have_received(:call).with(124)
      end
    end
  end
end

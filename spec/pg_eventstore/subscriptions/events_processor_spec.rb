# frozen_string_literal: true

RSpec.describe PgEventstore::EventsProcessor do
  let(:instance) { described_class.new(handler, graceful_shutdown_timeout: graceful_shutdown_timeout) }
  let(:handler) { proc { |raw_event| processed_events.push(raw_event['id']) } }
  let(:graceful_shutdown_timeout) { 5 }
  let(:processed_events) { [] }

  describe 'instance' do
    subject { instance }

    it { is_expected.to be_a(PgEventstore::Extensions::CallbacksExtension) }
  end

  describe '#feed' do
    subject { instance.feed(raw_events) }

    let(:raw_events) { [event1, event2] }
    let(:event1) { { 'id' => SecureRandom.uuid, 'global_position' => 2 } }
    let(:event2) { { 'id' => SecureRandom.uuid, 'global_position' => 3 } }
    let(:event_in_queue) { { 'id' => SecureRandom.uuid, 'global_position' => 1 } }
    let(:feed_callback) { proc { |latest_global_position| global_position_receiver.call(latest_global_position) } }
    let(:global_position_receiver) { double('Global position receiver') }

    before do
      instance.start
      # give runner time to try to consume first even and then get into sleep, so we can test changes in the chunk
      sleep 0.1
      instance.feed([event_in_queue])
      allow(global_position_receiver).to receive(:call)
      instance.define_callback(:feed, :after, feed_callback)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    context 'when runner is running' do
      it 'adds the given events to the queue' do
        expect { subject }.to change {
          instance.instance_variable_get(:@raw_events)
        }.from([event_in_queue]).to([event_in_queue, event1, event2])
      end
      it 'executes :feed action' do
        subject
        expect(global_position_receiver).to have_received(:call).with(3)
      end

      context 'when no events are fed' do
        let(:raw_events) { [] }

        it 'raises error' do
          expect { subject }.to raise_error(PgEventstore::EmptyChunkFedError)
        end
        it 'does not change the queue' do
          expect { subject rescue nil }.not_to change { instance.instance_variable_get(:@raw_events) }
        end
        it 'does not execute :feed action' do
          subject rescue nil
          expect(global_position_receiver).not_to have_received(:call).with(nil)
        end
      end

      context 'when last event is a link event' do
        let(:event2) { { 'id' => SecureRandom.uuid, 'global_position' => 3, 'link' => { 'global_position' => 5 } } }

        it "passes link's global position into :feed action" do
          subject
          expect(global_position_receiver).to have_received(:call).with(5)
        end
      end
    end

    context 'when runner is not in the :running state' do
      before do
        instance.stop_async.wait_for_finish
      end

      it 'does not change the queue' do
        expect { subject }.not_to change { instance.instance_variable_get(:@raw_events) }
      end
      it 'does not execute :feed action' do
        subject
        expect(global_position_receiver).not_to have_received(:call).with(nil)
      end
    end
  end

  describe '#events_left_in_chunk' do
    subject { instance.events_left_in_chunk }

    before do
      instance.start
      # give runner time to try to consume first even and then get into sleep, so we can test changes in the chunk
      sleep 0.1
      instance.feed([{ 'id' => SecureRandom.uuid, 'global_position' => 1 }])
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it "returns the size of raw events in the queue" do
      is_expected.to eq(1)
    end
  end

  describe '#clear_chunk' do
    subject { instance.clear_chunk }

    before do
      instance.start
      # give runner time to try to consume first even and then get into sleep, so we can test changes in the chunk
      sleep 0.1
      instance.feed([{ 'id' => SecureRandom.uuid, 'global_position' => 1 }])
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'clears current chunk' do
      expect { subject }.to change { instance.events_left_in_chunk }.from(1).to(0)
    end
  end

  describe 'async action' do
    subject { instance.feed(raw_events) }

    let(:raw_events) do
      [{ 'id' => SecureRandom.uuid, 'global_position' => 123 }, { 'id' => SecureRandom.uuid, 'global_position' => 124 }]
    end

    before do
      instance.start
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'processes the given events' do
      #  Let the runner start
      sleep 0.1
      expect { subject; sleep 0.6 }.to change { processed_events }.to(raw_events.map { _1['id'] })
    end
  end

  describe "on runner's death" do
    subject { instance.start }

    let(:on_error_cbx) { proc { |error| error_receiver.call(error) } }
    let(:error_receiver) { double('Error receiver') }
    let(:error) { StandardError.new('Oops!') }
    let(:handler) do
      proc { raise error }
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
      sleep 0.1
      # Feed the processor to trigger the error
      instance.feed([{ 'id' => SecureRandom.uuid, 'global_position' => 1 }])
      aggregate_failures do
        expect(error_receiver).not_to have_received(:call)
        sleep 0.5
        # After half a second we perform the same test over the same object, but with different expectation to prove
        # that the action is actually asynchronous
        expect(error_receiver).to have_received(:call).with(error)
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
      instance.feed([{ 'id' => SecureRandom.uuid, 'global_position' => 1 }])
      # Let the runner time to die
      sleep 0.6
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
    let(:raw_events) do
      [
        { 'id' => SecureRandom.uuid, 'global_position' => 123 },
        { 'id' => SecureRandom.uuid, 'global_position' => 124, 'link' => { 'global_position' => 125 } }
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
      sleep 0.1
      aggregate_failures do
        expect(global_position_receiver).not_to have_received(:call)
        # Feed the processor to trigger the event processing
        instance.feed(raw_events)
        # Let the runner to process the given events
        sleep 0.6
        # After half a second we perform the same test over the same object, but with different expectation to prove
        # that the action is actually asynchronous
        expect(global_position_receiver).to have_received(:call).with(123)
        expect(global_position_receiver).to have_received(:call).with(125)
      end
    end
  end
end

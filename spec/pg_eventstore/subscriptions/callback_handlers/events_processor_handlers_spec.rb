# frozen_string_literal: true

RSpec.describe PgEventstore::EventsProcessorHandlers do
  it { is_expected.to be_a(PgEventstore::Extensions::CallbackHandlersExtension) }

  describe '.consume_events' do
    subject { described_class.consume_events(consumer, callbacks, raw_events, raw_events_cond) }

    let(:callbacks) { PgEventstore::Callbacks.new }
    let(:consumer) do
      PgEventstore::EventsProcessorConsumer::Single.new(proc { |raw_event| processed_events.push(raw_event) })
    end
    let(:raw_events) { PgEventstore::SynchronizedArray.new([raw_event1, raw_event2]) }
    let(:raw_event1) { { 'global_position' => 1 } }
    let(:raw_event2) { { 'global_position' => 2 } }
    let(:raw_events_cond) { raw_events.new_cond }
    let(:processed_events) { [] }

    context 'when consumer is Single' do
      it 'processes first event in the queue' do
        expect { subject }.to change { processed_events }.to([raw_event1])
      end
      it 'removes processed event from the queue' do
        expect { subject }.to change { raw_events }.to([raw_event2])
      end
    end

    context 'when consumer is Multiple' do
      let(:consumer) do
        PgEventstore::EventsProcessorConsumer::Multiple.new(proc { |raw_events| processed_events.push(raw_events) })
      end

      it 'processes all events in the queue' do
        expect { subject }.to change { processed_events }.to([[raw_event1, raw_event2]])
      end
      it 'removes processed events from the queue' do
        expect { subject }.to change { raw_events }.to([])
      end
    end
  end

  describe '.after_runner_died' do
    subject { described_class.after_runner_died(callbacks, error) }

    let(:callbacks) { PgEventstore::Callbacks.new }
    let(:error) { StandardError.new('Oops!') }

    before do
      allow(callbacks).to receive(:run_callbacks).and_call_original
    end

    it 'runs :error callbacks' do
      subject
      expect(callbacks).to have_received(:run_callbacks).with(:error, error)
    end
  end

  describe '.before_runner_restored' do
    subject { described_class.before_runner_restored(callbacks) }

    let(:callbacks) { PgEventstore::Callbacks.new }

    before do
      allow(callbacks).to receive(:run_callbacks).and_call_original
    end

    it 'runs :restart callbacks' do
      subject
      expect(callbacks).to have_received(:run_callbacks).with(:restart)
    end
  end

  describe '.change_state' do
    subject { described_class.change_state(callbacks, state) }

    let(:callbacks) { PgEventstore::Callbacks.new }
    let(:state) { 'halting' }

    before do
      allow(callbacks).to receive(:run_callbacks).and_call_original
    end

    it 'runs :change_state callbacks' do
      subject
      expect(callbacks).to have_received(:run_callbacks).with(:change_state, state)
    end
  end
end

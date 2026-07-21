# frozen_string_literal: true

RSpec.describe PgEventstore::EventsProcessorHandlers do
  it { is_expected.to be_a(PgEventstore::Extensions::CallbackHandlersExtension) }

  describe '.consume_events' do
    subject { described_class.consume_events(consumer, callbacks, repository, repository_cond) }

    let(:callbacks) { PgEventstore::Callbacks.new }
    let(:consumer) do
      PgEventstore::EventsProcessorConsumer::Single.new(
        proc { |raw_event| processed_positions.push(raw_event['global_position']) }
      )
    end

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:event1) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
    let(:event2) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
    let(:indexes) { prepare_subscription_indexes([event1, event2]) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

    let(:repository) do
      repo = PgEventstore::Chunks::Repository.new
      repo.add_chunk(chunk)
      repo
    end
    let(:repository_cond) { repository.new_cond }
    let(:processed_positions) { [] }

    context 'when consumer is Single' do
      it 'processes first event in the queue' do
        expect { subject }.to change { processed_positions }.to([event1.global_position])
      end
      it 'removes processed event from the queue' do
        expect { subject }.to change { repository.size }.by(-1)
      end
    end

    context 'when consumer is Multiple' do
      let(:consumer) do
        PgEventstore::EventsProcessorConsumer::Multiple.new(
          proc { |raw_events| processed_positions.push(raw_events.map { _1['global_position'] }) }
        )
      end

      it 'processes all events in the queue' do
        expect { subject }.to change { processed_positions }.to([[event1.global_position, event2.global_position]])
      end
      it 'removes processed events from the queue' do
        expect { subject }.to change { repository.size }.to(0)
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

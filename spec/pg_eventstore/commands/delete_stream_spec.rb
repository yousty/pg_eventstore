# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::DeleteStream do
  let(:instance) { described_class.new(queries) }
  let(:queries) { PgEventstore::Queries.new(maintenance: maintenance_queries) }
  let(:maintenance_queries) { PgEventstore::MaintenanceQueries.new(PgEventstore.connection) }
  let(:streams_global_idx_queries) do
    PgEventstore::StreamsGlobalIndexQueries.new(PgEventstore.connection, query_strategy)
  end
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }

  describe '#call' do
    subject { instance.call(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

    context 'when stream exists' do
      let!(:events) do
        events = Array.new(2) { PgEventstore::Event.new }
        PgEventstore.client.append_to_stream(stream, events)
      end
      let(:another_stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '2') }
      let(:another_events) do
        events = Array.new(2) { PgEventstore::Event.new }
        PgEventstore.client.append_to_stream(another_stream, events)
      end

      it 'deletes events of the given stream' do
        expect { subject }.to change { safe_read(stream) }.from(events).to([])
      end
      it { is_expected.to eq(true) }
      it 'deletes related events global index' do
        expect { subject }.to change {
          query_strategy.exec_params(
            'select global_position from events_global_index where global_position = ANY($1::bigint[])',
            [events.map(&:global_position)]
          ).map { _1['global_position'] }
        }.to([])
      end
      it 'deletes StreamsGlobalIndex' do
        expect { subject }.to change { streams_global_idx_queries.find_by(stream) }.to(nil)
      end
      it 'does not delete events of another stream' do
        expect { subject }.not_to change { safe_read(another_stream) }
      end
      it 'does not delete events global index of another stream' do
        expect { subject }.not_to change {
          query_strategy.exec_params(
            'select global_position from events_global_index where global_position = ANY($1::bigint[])',
            [another_events.map(&:global_position)]
          ).map { _1['global_position'] }.sort
        }.from(another_events.map(&:global_position))
      end
      it 'does not delete StreamGlobalIndex of another stream' do
        expect { subject }.not_to change { streams_global_idx_queries.find_by(another_stream) }
      end
    end

    context 'when "all" stream is given' do
      let(:stream) { PgEventstore::Stream.all_stream }

      it 'raises error' do
        expect { subject }.to(
          raise_error(
            PgEventstore::SystemStreamError,
            "Can't perform this action with #{stream.inspect} system stream."
          )
        )
      end
    end

    context 'when stream does not exist' do
      let(:another_stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '2') }
      let!(:events) do
        events = Array.new(2) { PgEventstore::Event.new }
        PgEventstore.client.append_to_stream(another_stream, events)
      end

      it { is_expected.to eq(false) }
      it 'does not delete another stream' do
        expect { subject }.not_to change { safe_read(another_stream).map(&:id) }.from(events.map(&:id))
      end
    end
  end
end

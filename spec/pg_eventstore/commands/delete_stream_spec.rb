# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::DeleteStream do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(transactions: transaction_queries, maintenance: maintenance_queries)
  end
  let(:transaction_queries) { PgEventstore::TransactionQueries.new(PgEventstore.connection) }
  let(:maintenance_queries) { PgEventstore::MaintenanceQueries.new(PgEventstore.connection) }

  describe '#call' do
    subject { instance.call(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

    context 'when stream exists' do
      let!(:events) do
        events = Array.new(2) { PgEventstore::Event.new }
        PgEventstore.client.append_to_stream(stream, events)
      end

      it 'deletes it' do
        expect { subject }.to change { safe_read(stream).map(&:id) }.from(events.map(&:id)).to([])
      end
      it { is_expected.to eq(true) }
    end

    context 'when system stream is given' do
      let(:stream) { PgEventstore::Stream.system_stream('$streams') }

      it 'raises error' do
        expect { subject }.to(
          raise_error(
            PgEventstore::SystemStreamError,
            "Can't perform this action with #{stream.inspect} system stream."
          )
        )
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

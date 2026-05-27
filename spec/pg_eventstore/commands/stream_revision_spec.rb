# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::StreamRevision do
  let(:instance) { described_class.new(queries) }
  let(:queries) { PgEventstore::Queries.new(streams_global_index: streams_global_index_queries) }
  let(:streams_global_index_queries) do
    PgEventstore::StreamsGlobalIndexQueries.new(
      PgEventstore.connection, PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection)
    )
  end

  describe '#call' do
    subject { instance.call(stream) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    context 'when stream exists' do
      before do
        PgEventstore.client.append_to_stream(stream, [PgEventstore::Event.new] * 2)
      end

      it 'returns its revision' do
        is_expected.to eq(1)
      end
    end

    context 'when stream does not exist' do
      it 'returns non-existing stream revision' do
        is_expected.to eq(PgEventstore::Stream::NON_EXISTING_STREAM_REVISION)
      end
    end
  end
end

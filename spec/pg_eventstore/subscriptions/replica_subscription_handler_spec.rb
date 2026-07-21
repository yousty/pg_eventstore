# frozen_string_literal: true

# rubocop:disable RSpec/BeforeAfterAll
RSpec.describe PgEventstore::ReplicaSubscriptionHandler do
  let(:instance) { described_class.new(:default, :replica) }

  before(:context) do
    `
      PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_replica" \
      bundle exec rake pg_eventstore:drop pg_eventstore:create pg_eventstore:migrate
    `
  end

  after(:context) do
    `
      PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore_replica" \
      bundle exec rake pg_eventstore:drop
    `
  end

  before do
    PgEventstore.configure(name: :replica) do |config|
      config.pg_uri = 'postgresql://postgres:postgres@localhost:5532/eventstore_replica'
      config.eventstore_role = PgEventstore::Config::NodeRole::REPLICA
    end
    PgEventstore.configure do |config|
      config.eventstore_role = PgEventstore::Config::NodeRole::PRIMARY
    end
    PgEventstore::TestHelpers.clean_up_db(:replica)
  end

  after do
    PgEventstore.connection(:replica).shutdown
  end

  describe '#call' do
    subject { instance.call(indexes) }

    let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }
    let(:query_strategy_replica) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection(:replica)) }

    let(:replica_queries) do
      PgEventstore::ReplicaQueries.new(PgEventstore.connection, query_strategy)
    end
    let(:replica_queries_replica) do
      PgEventstore::ReplicaQueries.new(PgEventstore.connection(:replica), query_strategy_replica)
    end

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

    let(:event1) do
      event = PgEventstore::Event.new(
        type: 'Foo',
        data: { 'foo' => 'baz' },
        metadata: { 'foo' => '1' },
        markers: %w[foo baz]
      )
      PgEventstore.client.append_to_stream(stream1, event)
    end
    let(:event2) do
      event = PgEventstore::Event.new(
        type: 'Bar',
        data: { 'bar' => 'baz' },
        metadata: { 'bar' => '1' },
        markers: %w[bar baz]
      )
      PgEventstore.client.append_to_stream(stream2, event)
    end
    let(:event3) do
      event = PgEventstore::Event.new(
        type: 'Foo',
        data: { 'foo' => 'baz' },
        metadata: { 'foo' => '1' },
        markers: %w[foo baz]
      )
      PgEventstore.client.append_to_stream(stream1, event)
    end

    let(:indexes) { prepare_subscription_indexes([event1, event2, event3]) }

    before do
      indexes
    end

    shared_examples 'successful replication' do
      it 'has correct snapshot' do
        subject
        markers_index = replica_queries.load_event_markers_index(indexes)
        markers = replica_queries.load_markers(markers_index)
        events_index = replica_queries.load_events_global_index(indexes)
        streams_index = replica_queries.load_streams_global_index(events_index)
        partitions = replica_queries.load_partitions(events_index)
        aggregate_failures do
          expect(replica_queries_replica.load_events(indexes)).to eq(replica_queries.load_events(indexes))
          expect(replica_queries_replica.load_event_markers_index(indexes)).to eq(markers_index)
          expect(replica_queries_replica.load_markers(markers_index)).to eq(markers)
          expect(replica_queries_replica.load_events_global_index(indexes)).to eq(events_index)
          expect(replica_queries_replica.load_streams_global_index(events_index)).to eq(streams_index)
          expect(replica_queries_replica.load_partitions(events_index).map(&:options_hash)).to(
            eq(partitions.map(&:options_hash))
          )
          expect([event1, event2, event3]).to(
            eq(PgEventstore.client(:replica).read(PgEventstore::Stream.all_stream))
          )
        end
      end
    end

    context 'when events to replicate does not exist in the replica' do
      it_behaves_like 'successful replication'
    end

    context 'when some event to replicate already exist in the replica' do
      before do
        instance.call([indexes[0]])
      end

      it_behaves_like 'successful replication'
    end
  end
end
# rubocop:enable RSpec/BeforeAfterAll

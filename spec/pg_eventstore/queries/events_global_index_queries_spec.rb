# frozen_string_literal: true

RSpec.describe PgEventstore::EventsGlobalIndexQueries do
  let(:instance) { described_class.new(PgEventstore.connection, query_strategy) }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }

  describe '#index_events' do
    subject { instance.index_events(raw_events, affected_partitions, stream_idx_id) }

    let(:event_queries) { PgEventstore::EventQueries.new(PgEventstore.connection) }
    let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

    let(:event) { PgEventstore::Event.new(type: 'Foo', stream_revision: 0) }
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:affected_partition) do
      PgEventstore::Partition.new(
        **PgEventstore::Utils.deep_transform_keys(
          partition_queries.event_type_partition(stream, event.type),
          &:to_sym
        )
      )
    end
    let(:raw_event) { event_queries.insert(stream, [event]).first }

    let(:raw_events) { [raw_event] }
    let(:affected_partitions) { [affected_partition] }
    let(:stream_idx_id) { 1 }

    before do
      partition_queries.create_partitions(stream, event.type)
    end

    it 'creates events_global_index based on the given input' do
      expect { subject }.to change {
        query_strategy.exec('select count(*) as c_all from events_global_index').first['c_all']
      }.by(1)
    end

    describe 'created events_global_index' do
      let(:created_index) do
        query_strategy.exec('select * from events_global_index order by global_position limit 1').first
      end

      before do
        subject
      end

      it 'has correct attributes' do
        aggregate_failures do
          expect(created_index['global_position']).to eq(raw_event['global_position']).and be > 0
          expect(created_index['stream_revision']).to eq(event.stream_revision)
          expect(created_index['context_partition_id']).to eq(affected_partition.parent_context_partition_id)
          expect(created_index['stream_name_partition_id']).to eq(affected_partition.parent_stream_name_partition_id)
          expect(created_index['event_type_partition_id']).to eq(affected_partition.id)
          expect(created_index['streams_global_index_id']).to eq(stream_idx_id)
        end
      end
    end
  end

  describe '#fetch_indexes_for_subscriptions' do
    let(:event_subscription_position_queries) do
      PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection)
    end

    describe 'grouping result by subscription id' do
      subject { instance.fetch_indexes_for_subscriptions(grouped_opts) }

      let(:grouped_opts) do
        max_pos = query_strategy.exec(
          'select max(subscription_position) as max_pos from event_subscription_positions'
        ).first['max_pos'] || 0
        {
          subscription1.id => { from_position: 1, to_position: max_pos, max_count: 1000 },
          subscription2.id => { from_position: 1, to_position: max_pos, max_count: 1000 },
        }
      end

      let(:subscription1) do
        SubscriptionsHelper.create_with_connection(
          name: 'FooSub', set: subscriptions_set.name, options: { filter: { event_types: ['Foo'] } }
        )
      end
      let(:subscription2) do
        SubscriptionsHelper.create_with_connection(
          name: 'BarSub', set: subscriptions_set.name, options: { filter: { event_types: ['Bar'] } }
        )
      end
      let(:subscriptions_set) { SubscriptionsSetHelper.create }

      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let!(:event1) do
        event = PgEventstore::Event.new(type: 'Foo')
        PgEventstore.client.append_to_stream(stream, event)
      end
      let!(:event2) do
        event = PgEventstore::Event.new(type: 'Bar')
        PgEventstore.client.append_to_stream(stream, event)
      end

      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      before do
        subscription1.lock!(subscriptions_set.id)
        subscription2.lock!(subscriptions_set.id)
        reset_events_subscription_position
        event_subscription_position_queries.assign_subscription_position
      end

      it 'returns EventGlobalIndex-es grouped by subscription id' do
        foo_partition_id = partition_queries.event_type_partition(stream, 'Foo')['id']
        bar_partition_id = partition_queries.event_type_partition(stream, 'Bar')['id']
        is_expected.to(
          eq(
            subscription1.id => [
              PgEventstore::EventGlobalIndex::SubscriptionRepr.new(
                global_position: event1.global_position,
                event_type_partition_id: foo_partition_id,
                subscription_position: 1
              ),
            ],
            subscription2.id => [
              PgEventstore::EventGlobalIndex::SubscriptionRepr.new(
                global_position: event2.global_position,
                event_type_partition_id: bar_partition_id,
                subscription_position: 2
              ),
            ]
          )
        )
      end
    end
  end

  describe '#max_global_position' do
    subject { instance.max_global_position }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let!(:events) do
      event = PgEventstore::Event.new(type: 'Foo')
      PgEventstore.client.append_to_stream(stream, Array.new(5) { event })
    end

    it 'returns max global_position' do
      is_expected.to eq(events.last.global_position)
    end
  end

  describe '#global_positions_from_db' do
    subject { instance.global_positions_from_db([non_existing_event, persisted_event]) }

    let(:persisted_event) do
      stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
      PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
    end
    let(:non_existing_event) do
      PgEventstore::Event.new(global_position: -1)
    end

    it 'returns global positions of existing events' do
      is_expected.to eq([persisted_event.global_position])
    end
  end
end

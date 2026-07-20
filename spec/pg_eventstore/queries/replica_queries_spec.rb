# frozen_string_literal: true

RSpec.describe PgEventstore::ReplicaQueries do
  let(:instance) { described_class.new(PgEventstore.connection, query_strategy) }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }

  describe '#load_subscription_positions' do
    subject { instance.load_subscription_positions(indexes) }

    let(:indexes) { [index1, index2] }
    let(:index1) do
      PgEventstore::EventGlobalIndex::SubscriptionRepr.new(
        global_position: 1, subscription_position: 1, event_type_partition_id: 1
      )
    end
    let(:index2) do
      PgEventstore::EventGlobalIndex::SubscriptionRepr.new(
        global_position: 3, subscription_position: 3, event_type_partition_id: 1
      )
    end

    context 'when there are no records in the database' do
      it { is_expected.to eq([]) }
    end

    context 'when there is a record in the database in the range of first and last indexes' do
      context 'when a record in the database is among the indexes' do
        before do
          query_strategy.exec(<<~SQL)
            insert into event_subscription_positions ("global_position", "subscription_position") values (3, 3)
          SQL
        end

        it 'returns its subscription_position' do
          is_expected.to eq([index2.subscription_position])
        end
      end

      context 'when a record in the database is not among the indexes' do
        before do
          query_strategy.exec(<<~SQL)
            insert into event_subscription_positions ("global_position", "subscription_position") values (2, 2)
          SQL
        end

        it { is_expected.to eq([]) }
      end
    end
  end

  describe '#load_events' do
    subject { instance.load_events(indexes) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:event1) do
      event = PgEventstore::Event.new(
        type: 'Foo',
        metadata: { 'foo' => '1' },
        data: { 'foo' => 'baz' },
        markers: %w[foo baz]
      )
      PgEventstore.client.append_to_stream(stream, event)
    end
    let(:event2) { PgEventstore.client.link_to(stream, event1) }
    let(:indexes) { prepare_subscription_indexes([event1, event2]) }

    let(:uuid1) { '00000000-0000-0000-0000-000000000001' }
    let(:uuid2) { '00000000-0000-0000-0000-000000000002' }

    before do
      stub_const("#{described_class}::MAX_PARTITIONS_TO_RESOLVE_PER_CALL", 1)
      allow(SecureRandom).to receive(:uuid_v7).and_return(uuid1, uuid2)
    end

    it 'loads raw representation of the events' do
      is_expected.to(
        eq(
          [
            PgEventstore::RawEvent.new(
              id: uuid1,
              context: stream.context,
              stream_name: stream.stream_name,
              stream_id: stream.stream_id,
              global_position: event1.global_position,
              stream_revision: event1.stream_revision,
              data: event1.data,
              metadata: event1.metadata,
              created_at: event1.created_at,
              type: event1.type
            ),
            PgEventstore::RawEvent.new(
              id: uuid2,
              context: stream.context,
              stream_name: stream.stream_name,
              stream_id: stream.stream_id,
              global_position: event2.global_position,
              stream_revision: event2.stream_revision,
              data: event2.data,
              metadata: event2.metadata,
              created_at: event2.created_at,
              type: event2.type,
              link_partition_id: event2.link_partition_id,
              link_global_position: event2.link_global_position
            ),
          ]
        )
      )
    end
  end

  describe '#load_events_global_index' do
    subject { instance.load_events_global_index(indexes) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:event1) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Foo')) }
    let(:event2) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(type: 'Bar')) }
    let(:indexes) { prepare_subscription_indexes([event1, event2]) }

    before do
      indexes
    end

    it 'loads EventGlobalIndex-es' do
      is_expected.to eq(read_event_indexes([event1, event2]))
    end
  end

  describe '#load_streams_global_index' do
    subject { instance.load_streams_global_index(indexes) }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

    let(:event1) { PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'Foo')) }
    let(:event2) { PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'Bar')) }
    let(:another_event) { PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'Baz')) }

    let(:indexes) { read_event_indexes([event1, event2]) }

    before do
      indexes
      another_event
    end

    it 'returns StreamGlobalIndex-es with revisions, adjusted to the given event indexes revisions' do
      is_expected.to(
        eq(
          [
            PgEventstore::StreamGlobalIndex.new(
              id: indexes.first.streams_global_index_id,
              partition_id: indexes.first.stream_name_partition_id,
              stream_id: stream1.stream_id,
              stream_revision: event1.stream_revision,
              starting_position: event1.global_position
            ),
            PgEventstore::StreamGlobalIndex.new(
              id: indexes.last.streams_global_index_id,
              partition_id: indexes.last.stream_name_partition_id,
              stream_id: stream2.stream_id,
              stream_revision: event2.stream_revision,
              starting_position: event2.global_position
            ),
          ]
        )
      )
    end
  end

  describe '#load_event_markers_index' do
    subject { instance.load_event_markers_index(indexes) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(markers: %w[foo bar])) }
    let(:indexes) { prepare_subscription_indexes([event]) }

    it 'loads event marker indexes' do
      is_expected.to(eq(read_event_marker_indexes([event])))
    end
  end

  describe '#load_markers' do
    subject { instance.load_markers(indexes) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(markers: %w[foo bar])) }
    let(:indexes) { read_event_marker_indexes([event]) }

    it 'loads event markers' do
      is_expected.to(
        eq(
          [
            PgEventstore::EventMarker.new(id: indexes.first.marker_id, name: 'foo'),
            PgEventstore::EventMarker.new(id: indexes.last.marker_id, name: 'bar'),
          ]
        )
      )
    end
  end

  describe '#load_partitions' do
    subject { instance.load_partitions(indexes) }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
    let(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

    let(:event1) { PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new(type: 'Foo')) }
    let(:event2) { PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new(type: 'Bar')) }
    let(:another_event) { PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new(type: 'Baz')) }

    let(:indexes) { read_event_indexes([event1, event2]) }

    before do
      indexes
      another_event
    end

    it 'loads all partitions of the given indexes' do
      partitions = query_strategy.exec("select * from partitions where context != 'BarCtx' order by id").map do |attrs|
        PgEventstore::Partition.new(**attrs.transform_keys(&:to_sym))
      end
      expect(subject.map(&:options_hash)).to eq(partitions.map(&:options_hash))
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventsGlobalIndexQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    # @param query_strategy [PgEventstore::QueryStrategy]
    def initialize(connection, query_strategy)
      @connection = connection
      @query_strategy = query_strategy
    end

    # @param raw_events [Array<Hash>]
    # @param affected_partitions [Array<PgEventstore::Partition>]
    # @param stream_index_id [Integer]
    # @return [Array<PgEventstore::EventGlobalIndex::WriteApiRepr>]
    def index_events(raw_events, affected_partitions, stream_index_id)
      partitions = affected_partitions.to_h { [_1.event_type, _1] }
      values = raw_events.map do |event_attrs|
        values = [
          event_attrs['global_position'],
          event_attrs['stream_revision'],
          partitions[event_attrs['type']].parent_context_partition_id,
          partitions[event_attrs['type']].parent_stream_name_partition_id,
          partitions[event_attrs['type']].id,
          stream_index_id,
        ]
        "(#{values.join(', ')})"
      end
      values = values.join(',')

      result = @query_strategy.exec(<<~SQL)
        INSERT INTO events_global_index
          ("global_position", "stream_revision", "context_partition_id", "stream_name_partition_id",
           "event_type_partition_id", "streams_global_index_id")
        VALUES #{values}
        RETURNING global_position, stream_revision, event_type_partition_id
      SQL
      # "returning" statement has no guarantees about the order in which rows are returned. Thus, sort them explicitly
      deserialize(result, repr: EventGlobalIndex::ReprType::WRITE_API).sort_by(&:stream_revision)
    end

    # @param grouped_opts [Hash]
    # @return [Hash<Integer, Array<PgEventstore::SubscriptionRepr>>]
    def fetch_indexes_for_subscriptions(grouped_opts)
      builders = grouped_opts.map do |subscription_id, opts|
        filter = QueryBuilders::SubscriptionEventsFiltering.build(subscription_id, opts)
        filter.to_sql_builder.select("#{subscription_id} as subscription_id")
      end
      final_builder = SQLBuilder.union_builders(builders)
      res = @query_strategy.exec_params(*final_builder.to_exec_params)
      res = res.group_by { _1['subscription_id'] }
      res.to_h do |sid, indexes|
        [
          sid,
          indexes.map do |attrs|
            EventGlobalIndex::SubscriptionRepr.new(**attrs.except('subscription_id').transform_keys(&:to_sym))
          end,
        ]
      end
    end

    # @param indexes [Array<EventGlobalIndex::ReadApiRepr>, Array<EventGlobalIndex::SubscriptionRepr>]
    # @param resolve_link_tos [Boolean]
    # @param direction [String, Symbol, nil]
    # @return [Array<Hash>]
    def resolve_indexes(indexes, resolve_link_tos:, direction: nil)
      indexes = indexes.group_by(&:event_type_partition_id)
      partitions = partition_queries.find_by_ids(indexes.keys).to_h { [_1['id'], _1] }
      builders = indexes.map do |partition_id, idxs|
        partition = partitions[partition_id]
        events_filtering = QueryBuilders::EventsFiltering.new
        events_filtering.add_stream_attrs(context: partition['context'], stream_name: partition['stream_name'])
        events_filtering.add_event_types([partition['event_type']])
        builder = events_filtering.to_sql_builder
        builder.where('global_position = ANY(?)', idxs.map(&:global_position))
      end
      main_builder = SQLBuilder.union_builders(builders)
      with_sorted_events = SQLBuilder.new.select('*').from(main_builder)
      if direction
        with_sorted_events.order("global_position #{QueryBuilders::BasicFiltering::SQL_DIRECTIONS[direction]}")
      end
      raw_events = @query_strategy.exec_params(*with_sorted_events.to_exec_params).to_a
      resolve_link_tos ? links_resolver.resolve(raw_events) : raw_events
    end

    # @return [Integer, nil]
    def max_global_position
      builder = SQLBuilder.new.from(QueryBuilders::EventsGlobalIndexFiltering::PRIMARY_TABLE_NAME)
      builder.select('max(global_position) as max_global_position')
      @query_strategy.exec_params(*builder.to_exec_params).first['max_global_position']
    end

    # Takes an array of potentially persisted events and loads their ids from db. Those ids can be later used to check
    # whether events are actually existing events.
    # @param events [Array<PgEventstore::Event>]
    # @return [Array<Integer>]
    def global_positions_from_db(events)
      builder = SQLBuilder.new.from(QueryBuilders::EventsGlobalIndexFiltering::PRIMARY_TABLE_NAME)
      builder.where('global_position = ANY(?::bigint[])', events.map(&:global_position))
      @query_strategy.exec_params(*builder.to_exec_params).map { _1['global_position'] }
    end

    private

    # @return [PgEventstore::PartitionQueries]
    def partition_queries
      PartitionQueries.new(connection)
    end

    # @return [PgEventstore::LinksResolver]
    def links_resolver
      LinksResolver.new(connection, @query_strategy)
    end

    # @param repr [Symbol, nil]
    # @return [Array<PgEventstore::EventGlobalIndex>, Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>,
    #   Array<PgEventstore::EventGlobalIndex::ReadApiRepr>, Array<PgEventstore::EventGlobalIndex::WriteApiRepr>,
    #   Array<PgEventstore::EventGlobalIndex::RevisionCheckRepr>]
    def deserialize(pg_result, repr: nil)
      pg_result.map do |attrs|
        EventGlobalIndex.create_representation(attrs.transform_keys(&:to_sym), repr:)
      end
    end
  end
end

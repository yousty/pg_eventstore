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
    # @return [void]
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

      @query_strategy.exec(<<~SQL)
        INSERT INTO events_global_index
          ("global_position", "stream_revision", "context_partition_id", "stream_name_partition_id",
           "event_type_partition_id", "streams_global_index_id")
        VALUES #{values}
      SQL
    end

    # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
    # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
    # @return [Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
    def fetch_indexes_for_revision_validation(filters_collection, cursor)
      sql_builder = QueryBuilders::EventsGlobalIndexFiltering.sql_builder_for_revision_validation_per_type(
        filters_collection, cursor
      )
      deserialize(@query_strategy.exec_params(*sql_builder.to_exec_params), repr: EventGlobalIndex::ReprType::READ_API)
    end

    # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
    # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
    # @return [Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
    def fetch_indexes_for_read_api(filters_collection, cursor)
      if filters_collection.collection.any?(&:ambiguous_event_type?)
        filters_collection = expand_event_types(filters_collection)
      end
      sql_builder = QueryBuilders::EventsGlobalIndexFiltering.sql_builder_for_read_common(filters_collection, cursor)
      deserialize(@query_strategy.exec_params(*sql_builder.to_exec_params), repr: EventGlobalIndex::ReprType::READ_API)
    end

    # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
    # @param cursor [PgEventstore::QueryBuilders::ReadCursor::StreamCursor]
    # @return [Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
    def fetch_grouped_indexes_for_read_api(filters_collection, cursor)
      if filters_collection.collection.any?(&:ambiguous_event_type?)
        filters_collection = expand_event_types(filters_collection)
      end
      sql_builder = QueryBuilders::EventsGlobalIndexFiltering.sql_builder_for_read_grouped(filters_collection, cursor)
      deserialize(@query_strategy.exec_params(*sql_builder.to_exec_params), repr: EventGlobalIndex::ReprType::READ_API)
    end

    # @param indexes [Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
    # @param resolve_link_tos [Boolean]
    # @return [PgEventstore::Chunks::Repository]
    def compute_read_api_chunks_repo(indexes, resolve_link_tos)
      repo = Chunks::Repository.new
      repo.add_chunk(Chunks::ReadApiEventsIndexChunk.new(indexes, connection, @query_strategy, resolve_link_tos))
      repo
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

    # @param filters_collection [PgEventstore::QueryBuilders::Filters::Collection]
    # @return [PgEventstore::QueryBuilders::Filters::Collection]
    def expand_event_types(filters_collection)
      filter_rows = filters_collection.collection
      to_expand = filter_rows.select(&:ambiguous_event_type?)
      rest_filter_rows = filter_rows - to_expand
      partition_builders = to_expand.map do |filter_row|
        partitions_filtering = QueryBuilders::PartitionsFiltering.new
        partitions_filtering.with_event_types
        partitions_filtering.add_filter_row(filter_row)
        partitions_filtering.to_sql_builder.unselect.select('context, stream_name, event_type')
      end
      final_partition_builder = SQLBuilder.union_builders(partition_builders)
      adjuster_filters_collection = QueryBuilders::Filters::Collection.new
      expanded_partitions_list = @query_strategy.exec_params(*final_partition_builder.to_exec_params).to_a
      if expanded_partitions_list.empty?
        # Failed to fetch partitions from the database, because no related partitions exist yet by the given criteria
        event_type_filter = QueryBuilders::Filters::EventTypeFilter.null_filter
        adjuster_filters_collection.add_event_type(event_type_filter)
      else
        expanded_partitions_list.each do |attrs|
          stream_filter = QueryBuilders::Filters::StreamFilter.new(
            context: attrs['context'],
            stream_name: attrs['stream_name']
          )
          event_type_filter = QueryBuilders::Filters::EventTypeFilter.new(value: attrs['event_type'], prefix: false)
          adjuster_filters_collection.add_stream(stream_filter)
          adjuster_filters_collection.add_event_type(event_type_filter)
        end
      end
      rest_filter_rows.each do |filter_row|
        adjuster_filters_collection.add_stream(filter_row.stream_filter) if filter_row.stream_filter
        filter_row.event_type_filters.each(&adjuster_filters_collection.method(:add_event_type))
      end
      adjuster_filters_collection
    end

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
    #   Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
    def deserialize(pg_result, repr: nil)
      pg_result.map do |attrs|
        EventGlobalIndex.create_representation(attrs.transform_keys(&:to_sym), repr:)
      end
    end
  end
end

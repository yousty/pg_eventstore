# frozen_string_literal: true

module PgEventstore
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
        index = EventGlobalIndex.new(
          global_position: event_attrs['global_position'],
          stream_revision: event_attrs['stream_revision'],
          context_partition_id: partitions[event_attrs['type']].parent_context_partition_id,
          stream_name_partition_id: partitions[event_attrs['type']].parent_stream_name_partition_id,
          event_type_partition_id: partitions[event_attrs['type']].id,
          streams_global_index_id: stream_index_id
        )
        "(#{index.to_a.join(', ')})"
      end
      values = values.join(',')
      columns = EventGlobalIndex.members.map { %("#{_1}") }.join(', ')

      @query_strategy.exec(%(INSERT INTO events_global_index (#{columns}) VALUES #{values}))
    end

    def fetch_indexes_for_read_api(filters_collection, pagination_options, resolve_link_tos)
      if filters_collection.collection.any?(&:ambiguous_event_type?)
        filters_collection = expand_event_types(filters_collection)
      end
      sql_builder = QueryBuilders::EventsGlobalIndexFiltering.sql_builder_for_read_common(
        filters_collection, pagination_options
      )
      raw_indexes = deserialize(@query_strategy.exec_params(*sql_builder.to_exec_params))
      repo = RawEntities::Repository.new
      repo.add_chunk(
        RawEntities::EventsIndexChunk.new(
          raw_indexes, connection, @query_strategy, resolve_link_tos || false
        )
      )
      repo
    end

    def fetch_grouped_indexes_for_read_api(filters_collection, pagination_options, resolve_link_tos)
      if filters_collection.collection.any?(&:ambiguous_event_type?)
        filters_collection = expand_event_types(filters_collection)
      end
      sql_builder = QueryBuilders::EventsGlobalIndexFiltering.sql_builder_for_read_grouped(
        filters_collection, pagination_options
      )
      raw_indexes = deserialize(@query_strategy.exec_params(*sql_builder.to_exec_params))
      repo = RawEntities::Repository.new
      repo.add_chunk(
        RawEntities::EventsIndexChunk.new(
          raw_indexes, connection, @query_strategy, resolve_link_tos || false
        )
      )
      repo
    end

    def fetch_indexes_for_subscriptions(grouped_opts)
      builders = grouped_opts.map do |subscription_id, opts|
        filter = QueryBuilders::SubscriptionEventsFiltering.build(subscription_id, opts)
        filter.to_sql_builder.select("#{subscription_id} as subscription_id")
      end
      final_builder = SQLBuilder.union_builders(builders)
      res = @query_strategy.exec_params(*final_builder.to_exec_params)
      res = res.group_by { _1['subscription_id'] }
      res.to_h { |sid, indexes| [sid, indexes.map { EventGlobalIndex.new(_1.except('subscription_id')) }] }
    end

    def resolve_indexes(indexes, direction:, resolve_link_tos:)
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
      with_sorted_events.order("global_position #{QueryBuilders::EventsFiltering::SQL_DIRECTIONS[direction]}")
      raw_events = @query_strategy.exec_params(*with_sorted_events.to_exec_params).to_a
      resolve_link_tos ? links_resolver.resolve(raw_events) : raw_events
    end

    def max_global_position
      builder = QueryBuilders::EventsGlobalIndexFiltering.new.to_sql_builder
      builder.unselect
      builder.select('max(global_position) as max_global_position')
      @query_strategy.exec_params(*builder.to_exec_params).to_a.first['max_global_position']
    end

    # Takes an array of potentially persisted events and loads their ids from db. Those ids can be later used to check
    # whether events are actually existing events.
    # @param events [Array<PgEventstore::Event>]
    # @return [Array<Integer>]
    def global_positions_from_db(events)
      builder = QueryBuilders::EventsGlobalIndexFiltering.new.to_sql_builder
      builder.unselect.select('global_position')
      builder.where('global_position = ANY(?::bigint[])', events.map(&:global_position))
      @query_strategy.exec_params(*builder.to_exec_params).to_a.map { |attrs| attrs['global_position'] }
    end

    private

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
      @query_strategy.exec_params(*final_partition_builder.to_exec_params).each do |attrs|
        stream_filter = QueryBuilders::Filters::StreamFilter.new(
          context: attrs['context'],
          stream_name: attrs['stream_name']
        )
        event_type_filter = QueryBuilders::Filters::EventTypeFilter.new(value: attrs['event_type'], prefix: false)
        adjuster_filters_collection.add_stream(stream_filter)
        adjuster_filters_collection.add_event_type(event_type_filter)
      end
      rest_filter_rows.each do |filter_row|
        adjuster_filters_collection.add_stream(filter_row.stream_filter) if filter_row.stream_filter
        filter_row.event_type_filters.each(&adjuster_filters_collection.method(:add_event_type))
      end
      adjuster_filters_collection
    end

    def partition_queries
      PartitionQueries.new(connection)
    end

    def links_resolver
      LinksResolver.new(connection, @query_strategy)
    end

    def deserialize(pg_result)
      pg_result.map { EventGlobalIndex.new(_1) }
    end
  end
end

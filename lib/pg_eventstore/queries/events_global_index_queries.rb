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

    # @param indexes [Array<[Integer, Integer, String]>]
    # @return [void]
    def create_global_indexes(indexes)
      values = indexes.map do |global_position, partition_id, stream_id|
        "(#{global_position}, #{partition_id}, '#{PG::Connection.escape(stream_id)}')"
      end.join(',')

      @query_strategy.exec(<<~SQL)
        INSERT INTO events_global_index ("global_position", "partition_id", "stream_id") VALUES #{values}
      SQL
    end

    def grouped_indexes(grouped_opts)
      builders = grouped_opts.map do |group_id, opts|
        filter = QueryBuilders::EventsGlobalIndexFiltering.build_filter_from_subscription_options(opts)
        filter.to_sql_builder.select("#{group_id} as group_id")
      end
      final_builder = SQLBuilder.union_builders(builders)
      @query_strategy.exec_params(*final_builder.to_exec_params).group_by { _1['group_id'] }
    end

    def resolve_indexes(indexes)
      indexes = indexes.group_by { _1['partition_id'] }
      partitions = partition_queries.find_by_ids(indexes.keys).to_h { [_1['id'], _1] }
      builders = indexes.map do |partition_id, idxs|
        partition = partitions[partition_id]
        builder = SQLBuilder.new.select('*').from(Event::PRIMARY_TABLE_NAME)
        builder.where(
          'context = ? and stream_name = ? and type = ? and global_position = ANY(?)',
          partition['context'],
          partition['stream_name'],
          partition['event_type'],
          idxs.map { _1['global_position'] }
        )
      end
      main_builder = SQLBuilder.union_builders(builders)
      with_sorted_events = SQLBuilder.new.select('*').from(main_builder).order('global_position asc')
      links_resolver.resolve(@query_strategy.exec_params(*with_sorted_events.to_exec_params).to_a)
    end

    def max_global_position
      builder = QueryBuilders::EventsGlobalIndexFiltering.new.to_sql_builder
      builder.unselect
      builder.select('max(global_position) as max_global_position')
      @query_strategy.exec_params(*builder.to_exec_params).to_a.first['max_global_position']
    end

    private

    def partition_queries
      PartitionQueries.new(connection)
    end

    def links_resolver
      LinksResolver.new(connection, @query_strategy)
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class LinksResolver
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # Takes an array of events, look for link events in there and replaces link events with original events
    # @param raw_events [Array<Hash>]
    # @return [Array<Hash>]
    def resolve(raw_events)
      link_events = raw_events.select { _1['link_partition_id'] }.group_by { _1['link_partition_id'] }
      return raw_events if link_events.empty?

      original_events = load_original_events(link_events).to_h { |attrs| [attrs['id'], attrs] }
      raw_events.map do |attrs|
        original_event = original_events[attrs['link_id']]
        next attrs unless original_event

        original_event.merge('link' => attrs).merge(attrs.except(*original_event.keys))
      end
    end

    private

    # @param link_events [Hash{Integer => Array<Hash>}] partition id to link events association
    # @return [Array<Hash>] original events
    def load_original_events(link_events)
      partitions = partition_queries.find_by_ids(link_events.keys)
      sql_builders = partitions.map do |partition|
        sql_builder = SQLBuilder.new.select('*').from(partition['table_name'])
        sql_builder.where('id  = ANY(?::uuid[])', link_events[partition['id']].map { _1['link_id'] })
      end
      sql_builder = sql_builders[1..].each_with_object(sql_builders.first) do |builder, top_builder|
        top_builder.union(builder)
      end

      connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end.to_a
    end

    def partition_queries
      PartitionQueries.new(connection)
    end
  end
end

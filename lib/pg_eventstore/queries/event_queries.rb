# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @see PgEventstore::Client#read for more info
    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @return [Array<Hash>]
    def stream_events(stream, options)
      exec_params = QueryBuilders::EventsFiltering.events_filtering(stream, options).to_exec_params
      raw_events = connection.with do |conn|
        conn.exec_params(*exec_params)
      end.to_a
      raw_events = links_resolver.resolve(raw_events) if options[:resolve_link_tos]
      raw_events
    end

    # @param stream [PgEventstore::Stream]
    # @param events [Array<PgEventstore::Event>]
    # @return [Array<PgEventstore::Event>]
    def insert(stream, events)
      sql_rows_for_insert, values = prepared_statements(stream, events)
      columns = %w[id data metadata stream_revision link_global_position link_partition_id type context stream_name stream_id]

      sql = <<~SQL
        INSERT INTO events (#{columns.join(', ')})
          VALUES #{sql_rows_for_insert.join(', ')}
          RETURNING *
      SQL

      connection.with do |conn|
        conn.exec_params(sql, values)
      end.to_a
    end

    # @param stream [PgEventstore::Stream]
    # @param options_by_event_type [Array<Hash>] a set of options per an event type
    # @param options [Hash]
    # @option options [Boolean] :resolve_link_tos
    # @return [Array<Hash>]
    def grouped_events(stream, options_by_event_type, **options)
      builders = options_by_event_type.map do |filter|
        QueryBuilders::EventsFiltering.events_filtering(stream, filter)
      end
      final_builder = SQLBuilder.union_builders(builders.map(&:to_sql_builder))

      raw_events = connection.with do |conn|
        conn.exec_params(*final_builder.to_exec_params)
      end.to_a
      raw_events = links_resolver.resolve(raw_events) if options[:resolve_link_tos]
      raw_events
    end

    private

    # @param stream [PgEventstore::Stream]
    # @param events [Array<PgEventstore::Event>]
    # @return [Array<Array<String>, Array<Object>>]
    def prepared_statements(stream, events)
      positional_counter = 1
      values = []
      sql_rows_for_insert = events.map do |event|
        attributes = event.options_hash.slice(
          :id, :data, :metadata, :stream_revision, :link_global_position, :link_partition_id, :type
        )

        attributes = attributes.merge(stream.to_hash)
        prepared = attributes.values.map do |value|
          if value.nil?
            'DEFAULT'
          else
            "$#{positional_counter}".tap do
              values.push(value)
              positional_counter += 1
            end
          end
        end
        "(#{prepared.join(',')})"
      end
      [sql_rows_for_insert, values]
    end

    # @return [PgEventstore::LinksResolver]
    def links_resolver
      LinksResolver.new(connection, QueryStrategy::Foreground.new(connection))
    end
  end
end

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

    # @param stream [PgEventstore::Stream]
    # @param events [Array<PgEventstore::Event>]
    # @return [Array<Hash>]
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

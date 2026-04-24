# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class StreamsGlobalIndexQueries
    # @param connection [PgEventstore::Connection]
    # @param query_strategy [PgEventstore::QueryStrategy]
    def initialize(connection, query_strategy)
      @connection = connection
      @query_strategy = query_strategy
    end

    # @param attrs [Hash]
    # @return [void]
    def create_global_indexe(attrs)
      value = "(#{attrs[:partition_id]}, '#{PG::Connection.escape(attrs[:stream_id])}')"

      @query_strategy.exec(<<~SQL)
        INSERT INTO streams_global_index ("partition_id", "stream_id") VALUES #{value}
      SQL
    end

    # @param stream [PgEventstore::Stream]
    # @return [Integer, nil]
    def stream_revision(stream)
      sql_builder = SQLBuilder.new.from(Event::PRIMARY_TABLE_NAME).select('stream_revision')
      sql_builder.where('context = ? and stream_name = ? and stream_id = ?', *stream.to_a)
      sql_builder.order('stream_revision DESC').limit(1)
      connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end.to_a.dig(0, 'stream_revision')
    end

  end
end

# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionServiceQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @return [Integer]
    def current_database_id
      connection.with do |conn|
        conn.exec(<<~SQL)
          SELECT oid FROM pg_database WHERE datname = current_database() LIMIT 1
        SQL
      end.first['oid']
    end

    # @param database_id [Integer]
    # @return [Integer, nil]
    def smallest_uncommitted_global_position(database_id)
      connection.with do |conn|
        conn.exec_params(<<~SQL, [database_id])
          SELECT ((classid::bigint << 32) | objid::bigint) AS global_position
            FROM pg_locks
            WHERE locktype = 'advisory' AND database = $1
            ORDER BY classid, objid
            LIMIT 1
        SQL
      end.first&.dig('global_position')
    end

    def safe_global_position
      result = transaction_queries.transaction(read_only: true) do
        connection.with do |conn|
          conn.exec(<<~SQL)
            SELECT MAX(global_position) as global_position
              FROM events_horizon
              WHERE xact_id < pg_snapshot_xmin(pg_current_snapshot())
          SQL
        end
      end

      global_position = result.to_a.first&.dig('global_position')
      return global_position if global_position

      if global_position.nil? && !events_horizon_present?
        init_events_horizon
        return safe_global_position
      end
      # events_horizon table is not empty, but there is no safe position yet. Thus, we wait for the safe position by
      # returning 0 which will prevent from fetching events with gaps
      0
    end

    def events_horizon_present?
      result = connection.with do |conn|
        conn.exec(<<~SQL)
          SELECT true as presence FROM events_horizon LIMIT 1
        SQL
      end
      result.to_a.first&.dig('presence') || false
    end

    def init_events_horizon
      transaction_queries.transaction do
        return if events_horizon_present?

        max_pos = connection.with do |conn|
          conn.exec('SELECT MAX(global_position) FROM events')
        end
        max_pos = max_pos.to_a.first&.dig('global_position') || 0
        connection.with do |conn|
          conn.exec_params(<<~SQL, [max_pos])
            INSERT INTO events_horizon (global_position, xact_id) VALUES ($1, DEFAULT)
          SQL
        end
      end
    end

    private

    def transaction_queries
      TransactionQueries.new(connection)
    end
  end
end

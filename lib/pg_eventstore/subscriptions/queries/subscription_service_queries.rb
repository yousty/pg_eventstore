# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class SubscriptionServiceQueries
    # @return [Integer]
    DEFAULT_SAFE_POSITION = 0
    private_constant :DEFAULT_SAFE_POSITION

    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
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
      # returning default value which will prevent from fetching events with gaps
      DEFAULT_SAFE_POSITION
    end

    # @return [Boolean]
    def events_horizon_present?
      result = connection.with do |conn|
        conn.exec(<<~SQL)
          SELECT true as presence FROM events_horizon LIMIT 1
        SQL
      end
      result.to_a.first&.dig('presence') || false
    end

    # @return [void]
    def init_events_horizon
      transaction_queries.transaction do
        return if events_horizon_present?

        max_pos = connection.with do |conn|
          conn.exec('SELECT MAX(global_position) FROM events')
        end
        max_pos = max_pos.to_a.first&.dig('global_position') || DEFAULT_SAFE_POSITION
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

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
  end
end

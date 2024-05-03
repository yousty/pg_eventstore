# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class TransactionQueries
    ISOLATION_LEVELS = {
      read_committed: 'READ COMMITTED',
      repeatable_read: 'REPEATABLE READ',
      serializable: 'SERIALIZABLE'
    }.tap do |h|
      h.default = h[:serializable]
    end.freeze

    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param level [Symbol] transaction isolation level
    # @return [void]
    def transaction(level = :serializable)
      connection.with do |conn|
        # We are inside a transaction already - no need to start another one
        if [PG::PQTRANS_ACTIVE, PG::PQTRANS_INTRANS].include?(conn.transaction_status)
          next yield
        end

        pg_transaction(ISOLATION_LEVELS[level], conn) do
          yield
        end
      end
    end

    private

    # @param level [String] PostgreSQL transaction isolation level
    # @param pg_connection [PG::Connection]
    # @return [void]
    def pg_transaction(level, pg_connection)
      pg_connection.transaction do
        pg_connection.exec("SET TRANSACTION ISOLATION LEVEL #{level}")
        yield
      end
    rescue PG::TRSerializationFailure, PG::TRDeadlockDetected
      retry
    rescue MissingPartitions => error
      error.event_types.each do |event_type|
        transaction do
          partition_queries.create_partitions(error.stream, event_type)
        end
      rescue PG::UniqueViolation
        retry
      end
      retry
    end

    def partition_queries
      PartitionQueries.new(connection)
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class TransactionQueries
    # @return [Hash<Symbol => String>] symbol to transaction isolation level association
    ISOLATION_LEVELS = {
      read_committed: 'READ COMMITTED',
      repeatable_read: 'REPEATABLE READ',
      serializable: 'SERIALIZABLE',
    }.tap do |h|
      h.default = h[:serializable]
    end.freeze

    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param level [Symbol] transaction isolation level
    # @param read_only [Boolean] whether transaction is read-only
    # @return [void]
    def transaction(level = :serializable, read_only: false, &blk)
      connection.with do |conn|
        # We are inside a transaction already - no need to start another one
        next yield if [PG::PQTRANS_ACTIVE, PG::PQTRANS_INTRANS].include?(conn.transaction_status)

        pg_transaction(ISOLATION_LEVELS[level], read_only, conn, &blk)
      end
    end

    private

    # @param level [String] PostgreSQL transaction isolation level
    # @param read_only [Boolean]
    # @param pg_connection [PG::Connection]
    # @return [void]
    def pg_transaction(level, read_only, pg_connection, &)
      pg_connection.transaction do
        if read_only
          pg_connection.exec("SET TRANSACTION ISOLATION LEVEL #{level} READ ONLY")
        else
          pg_connection.exec("SET TRANSACTION ISOLATION LEVEL #{level}")
        end
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

    # @return [PgEventstore::PartitionQueries]
    def partition_queries
      PartitionQueries.new(connection)
    end
  end
end

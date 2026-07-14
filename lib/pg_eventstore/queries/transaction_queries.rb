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
    # @return [Integer]
    MAX_NUMBER_OF_UNIQUE_CONSTRAINTS_ERROR_RETRIES = 5

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
      retries_count = 0
      begin
        _transaction(pg_connection) do
          if read_only
            pg_connection.exec("SET TRANSACTION ISOLATION LEVEL #{level} READ ONLY")
          else
            pg_connection.exec("SET TRANSACTION ISOLATION LEVEL #{level}")
          end
          yield
        end
      rescue PG::TRSerializationFailure, PG::TRDeadlockDetected
        retry
      rescue PG::UniqueViolation
        retries_count += 1
        raise if retries_count >= MAX_NUMBER_OF_UNIQUE_CONSTRAINTS_ERROR_RETRIES

        retry
      rescue MissingPartitions => error
        error.event_types.each do |event_type|
          transaction do
            partition_queries.create_partitions(error.stream, event_type)
          end
        end
        retry
      end
    end

    # TODO: next pg gem release (presumably v1.6.4) should already include the fix of PG::Connection#transaction.
    #       Changes are already in master branch
    #       https://github.com/ged/ruby-pg/commit/c3d2aabd0a19d20bb1f2b2fa2e5b30f03b043aff
    #       Once it is released - change pg gem requirement in gemspec to '>= 1.6.4' and remove this implementation.
    # @param conn [PG::Connection]
    # rubocop:disable Lint/RescueException
    def _transaction(conn)
      rollback = false
      conn.exec('BEGIN')
      yield
    rescue PG::RollbackTransaction
      rollback = true
      perform_rollback(conn)
    rescue Exception
      rollback = true
      perform_rollback(conn)
      raise
    ensure
      unless rollback
        if Thread.current.status == 'aborting'
          perform_rollback(conn)
        else
          conn.exec('COMMIT')
        end
      end
    end
    # rubocop:enable Lint/RescueException

    def perform_rollback(conn)
      conn.cancel if conn.transaction_status == PG::PQTRANS_ACTIVE
      conn.block
      conn.exec('ROLLBACK')
    end

    # @return [PgEventstore::PartitionQueries]
    def partition_queries
      PartitionQueries.new(connection)
    end
  end
end

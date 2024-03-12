# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class TransactionQueries
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @return [void]
    def transaction
      connection.with do |conn|
        # We are inside a transaction already - no need to start another one
        if [PG::PQTRANS_ACTIVE, PG::PQTRANS_INTRANS].include?(conn.transaction_status)
          next yield
        end

        pg_transaction(conn) do
          yield
        end
      end
    end

    private

    # @param pg_connection [PG::Connection]
    # @return [void]
    def pg_transaction(pg_connection)
      pg_connection.transaction do
        pg_connection.exec("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")
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

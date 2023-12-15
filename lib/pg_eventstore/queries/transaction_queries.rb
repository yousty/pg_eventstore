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

        conn.transaction do
          conn.exec("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")
          yield
        end
      end
    rescue PG::TRSerializationFailure, PG::TRDeadlockDetected => e
      retry if [PG::PQTRANS_IDLE, PG::PQTRANS_UNKNOWN].include?(e.connection.transaction_status)
      raise
    end
  end
end

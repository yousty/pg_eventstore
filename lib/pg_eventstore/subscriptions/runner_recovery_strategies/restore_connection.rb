# frozen_string_literal: true

module PgEventstore
  module RunnerRecoveryStrategies
    # @!visibility private
    class RestoreConnection
      # @return [Integer] seconds
      TIME_BETWEEN_RETRIES = 5
      # @return [Array<StandardError>]
      EXCEPTIONS_TO_HANDLE = [PG::ConnectionBad, PG::UnableToSend, ConnectionPool::TimeoutError]

      include RunnerRecoveryStrategy

      # @param config_name [Symbol]
      def initialize(config_name)
        @config_name = config_name
      end

      def recovers?(error)
        EXCEPTIONS_TO_HANDLE.any? {error.is_a?(_1) }
      end

      def recover(error)
        loop do
          sleep TIME_BETWEEN_RETRIES

          connection.with do |conn|
            conn.exec('select version()')
            # No error was raised during the request. We are good to recover!
            return true
          end
        rescue *EXCEPTIONS_TO_HANDLE
        end
      end

      private

      # @return [PgEventstore::Connection]
      def connection
        PgEventstore.connection(@config_name)
      end
    end
  end
end

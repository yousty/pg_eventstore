# frozen_string_literal: true

module PgEventstore
  module QueryStrategy
    # @!visibility private
    class Async
      include QueryStrategy

      # @param connection [PgEventstore::Connection]
      def initialize(connection)
        @connection = connection
      end

      def exec(*)
        run(:send_query, *)
      end

      def exec_params(*)
        run(:send_query_params, *)
      end

      private

      def run(method, *exec_args)
        @connection.with do |conn|
          conn.public_send(method, *exec_args)
          loop do
            conn.consume_input
            break unless conn.is_busy

            Fiber.yield
          end

          last_result = nil
          while result = conn.get_result
            # Check whether result is successful. Raises error if it is not.
            # Related function is pg_result_check() in pg_result.c
            result.check_result
            last_result = result
          end
          last_result
        rescue AsyncRunner::Cancellation
          cancel_and_drain(conn)
          Fiber.current.kill
        end
      end

      # @param conn [PG::Connection]
      # @return [void]
      def cancel_and_drain(conn)
        cancellation_error = conn.cancel
        conn.sync_reset if cancellation_error

        while (result = conn.get_result)
          result.clear
        end
      rescue PG::Error
        # We have unexpected error during the cancellation process. No need to try to restore the connection at this
        # point and simply throw it out
        @connection.discard_current_connection
      end
    end
  end
end

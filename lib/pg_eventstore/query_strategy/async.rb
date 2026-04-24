# frozen_string_literal: true

module PgEventstore
  module QueryStrategy
    class Async
      include QueryStrategy

      def initialize(connection)
        @connection = connection
      end

      def exec(*, &)
        run(:send_query, *, &)
      end

      def exec_params(*, &)
        run(:send_query_params, *, &)
      end

      private

      def run(method, *exec_args, &)
        @connection.with do |conn|
          conn.public_send(method, *exec_args)
          loop do
            conn.consume_input
            break unless conn.is_busy

            Fiber.yield
          end

          last_result = nil
          while result = conn.get_result
            result.check_result
            case result.result_status
            when PG::PGRES_TUPLES_CHUNK
              yield result
            else
              last_result = result
            end
          end
          last_result
        end
      end
    end
  end
end

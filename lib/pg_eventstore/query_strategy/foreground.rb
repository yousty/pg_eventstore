# frozen_string_literal: true

module PgEventstore
  module QueryStrategy
    class Foreground
      include QueryStrategy

      def initialize(connection)
        @connection = connection
      end

      def exec(*exec_args)
        @connection.with do |conn|
          conn.exec(*exec_args)
        end
      end

      def exec_params(*exec_args)
        @connection.with do |conn|
          conn.exec_params(*exec_args)
        end
      end
    end
  end
end

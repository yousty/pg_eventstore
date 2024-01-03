# frozen_string_literal: true

module PgEventstore
  module CommandHandlers
    class SubscriptionRunnersCommands
      def initialize(config_name, runners)
        @config_name = config_name
        @runners = runners
      end

      def process
        queries.find_commands(@runners.map(&:id)).each do |command|
          case command[:name]
          when 'StopRunner'
            find_subscription_runner(command[:subscription_id])&.stop_async
          when 'RestoreRunner'
            find_subscription_runner(command[:subscription_id])&.restore
          when 'StartRunner'
            find_subscription_runner(command[:subscription_id])&.start
          else
            PgEventstore.logger&.warn(
              "#{self.class.name}: Don't know how to handle #{command[:name].inspect}. Details: #{command.inspect}."
            )
          end
          queries.delete(command[:id])
        end
      end

      private

      def queries
        SubscriptionCommandQueries.new(connection)
      end

      def connection
        PgEventstore.connection(@config_name)
      end

      def find_subscription_runner(subscription_id)
        @runners.find { |runner| runner.id == subscription_id }
      end
    end
  end
end

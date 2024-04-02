# frozen_string_literal: true

module PgEventstore
  module CommandHandlers
    class SubscriptionRunnersCommands
      AVAILABLE_COMMANDS = %i[Start Stop Restore].to_h { [_1, _1.to_s] }.freeze

      # @param config_name [Symbol]
      # @param runners [Array<PgEventstore::SubscriptionRunner>]
      def initialize(config_name, runners)
        @config_name = config_name
        @runners = runners
      end

      # Look up commands for all given SubscriptionRunner-s and execute them
      # @return [void]
      def process
        queries.find_commands(@runners.map(&:id)).each do |command|
          unless AVAILABLE_COMMANDS.values.include?(command[:name])
            PgEventstore.logger&.warn(
              "#{self.class.name}: Don't know how to handle #{command[:name].inspect}. Details: #{command.inspect}."
            )
            next
          end
          send(Utils.underscore_str(command[:name]), command[:subscription_id])
        ensure
          queries.delete(command[:id])
        end
      end

      private

      # @return [PgEventstore::SubscriptionCommandQueries]
      def queries
        SubscriptionCommandQueries.new(connection)
      end

      # @return [PgEventstore::Connection]
      def connection
        PgEventstore.connection(@config_name)
      end

      # @param subscription_id [Integer]
      # @return [PgEventstore::SubscriptionRunner, nil]
      def find_subscription_runner(subscription_id)
        @runners.find { |runner| runner.id == subscription_id }
      end

      # @param subscription_id [Integer]
      # @return [void]
      def start(subscription_id)
        find_subscription_runner(subscription_id)&.start
      end

      # @param subscription_id [Integer]
      # @return [void]
      def restore(subscription_id)
        find_subscription_runner(subscription_id)&.restore
      end

      # @param subscription_id [Integer]
      # @return [void]
      def stop(subscription_id)
        find_subscription_runner(subscription_id)&.stop_async
      end
    end
  end
end

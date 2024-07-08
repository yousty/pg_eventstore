# frozen_string_literal: true

module PgEventstore
  module CommandHandlers
    class SubscriptionRunnersCommands
      # @param config_name [Symbol]
      # @param runners [Array<PgEventstore::SubscriptionRunner>]
      # @param subscriptions_set_id [Integer]
      def initialize(config_name, runners, subscriptions_set_id)
        @config_name = config_name
        @runners = runners.to_h { |runner| [runner.id, runner] }
        @subscriptions_set_id = subscriptions_set_id
      end

      # Look up commands for all given SubscriptionRunner-s and execute them
      # @return [void]
      def process
        queries.find_commands(@runners.keys, subscriptions_set_id: @subscriptions_set_id).each do |command|
          command.exec_cmd(@runners[command.subscription_id]) if @runners[command.subscription_id]
          queries.delete(command.id)
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
    end
  end
end

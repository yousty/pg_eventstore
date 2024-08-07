# frozen_string_literal: true

module PgEventstore
  module CommandHandlers
    class SubscriptionFeederCommands
      # @param config_name [Symbol]
      # @param subscription_feeder [PgEventstore::SubscriptionFeeder]
      def initialize(config_name, subscription_feeder)
        @config_name = config_name
        @subscription_feeder = subscription_feeder
      end

      # Look up commands for the given SubscriptionFeeder and execute them
      # @return [void]
      def process
        queries.find_commands(@subscription_feeder.id).each do |command|
          command.exec_cmd(@subscription_feeder)
          queries.delete(command.id)
        end
      end

      private

      # @return [PgEventstore::SubscriptionsSetCommandQueries]
      def queries
        SubscriptionsSetCommandQueries.new(connection)
      end

      # @return [PgEventstore::Connection]
      def connection
        PgEventstore.connection(@config_name)
      end
    end
  end
end

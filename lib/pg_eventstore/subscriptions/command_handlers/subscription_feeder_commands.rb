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
          case command[:name]
          when 'StopAll'
            @subscription_feeder.stop_all
          when 'StartAll'
            @subscription_feeder.start_all
          else
            PgEventstore.logger&.warn(
              "#{self.class.name}: Don't know how to handle #{command[:name].inspect}. Details: #{command.inspect}."
            )
          end
          queries.delete(command[:id])
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

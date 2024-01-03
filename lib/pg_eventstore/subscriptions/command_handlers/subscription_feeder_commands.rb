# frozen_string_literal: true

module PgEventstore
  module CommandHandlers
    class SubscriptionFeederCommands
      def initialize(config_name, subscription_feeder)
        @config_name = config_name
        @subscription_feeder = subscription_feeder
      end

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

      def queries
        SubscriptionsSetCommandQueries.new(connection)
      end

      def connection
        PgEventstore.connection(@config_name)
      end
    end
  end
end

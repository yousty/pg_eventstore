# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeederCommands
    # @!visibility private
    class Ping < Base
      # @param subscription_feeder [PgEventstore::SubscriptionFeeder]
      # @return [void]
      def exec_cmd(subscription_feeder)
        queries(subscription_feeder.config_name).update(subscriptions_set_id, {})
      end

      private

      # @param config_name [Symbol]
      # @return [PgEventstore::SubscriptionsSetQueries]
      def queries(config_name)
        SubscriptionsSetQueries.new(PgEventstore.connection(config_name))
      end
    end
  end
end

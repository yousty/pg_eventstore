# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeederCommands
    # @!visibility private
    class StopAll < Base
      # @param subscription_feeder [PgEventstore::SubscriptionFeeder]
      # @return [void]
      def exec_cmd(subscription_feeder)
        subscription_feeder.stop_all
      end
    end
  end
end

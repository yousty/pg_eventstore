# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeederCommands
    # @!visibility private
    class Restore < Base
      # @param subscription_feeder [PgEventstore::SubscriptionFeeder]
      # @return [void]
      def exec_cmd(subscription_feeder)
        subscription_feeder.restore
      end
    end
  end
end

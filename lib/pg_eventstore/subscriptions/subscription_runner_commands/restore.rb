# frozen_string_literal: true

module PgEventstore
  module SubscriptionRunnerCommands
    # @!visibility private
    class Restore < Base
      # @param subscription_runner [PgEventstore::SubscriptionRunner]
      # @return [void]
      def exec_cmd(subscription_runner)
        subscription_runner.restore
      end
    end
  end
end

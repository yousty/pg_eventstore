# frozen_string_literal: true

module PgEventstore
  module SubscriptionRunnerCommands
    # @!visibility private
    class Restore < Base
      # @param subscription_runner [PgEventstore::SubscriptionRunner]
      # @return [void]
      def exec_cmd(subscription_runner)
        subscription_runner.within_state(:dead) do
          subscription_runner.subscription.update(
            restart_count: 0,
            last_restarted_at: nil,
            last_error: nil,
            last_error_occurred_at: nil
          )
        end
        subscription_runner.restore
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  module RunnerRecoveryStrategies
    # @!visibility private
    class RestoreSubscriptionFeeder
      include RunnerRecoveryStrategy

      # @param subscriptions_set_lifecycle [PgEventstore::SubscriptionsSetLifecycle]
      def initialize(subscriptions_set_lifecycle:)
        @subscriptions_set_lifecycle = subscriptions_set_lifecycle
      end

      def recovers?(_error)
        true
      end

      def recover(_error)
        subscriptions_set = @subscriptions_set_lifecycle.persisted_subscriptions_set
        return false if subscriptions_set.restart_count >= subscriptions_set.max_restarts_number

        sleep subscriptions_set.time_between_restarts
        true
      end
    end
  end
end

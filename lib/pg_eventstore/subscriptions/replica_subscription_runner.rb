# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  # We need to differentiate between replica subscription runner and regular subscription runner. They both have the
  # same functional though
  class ReplicaSubscriptionRunner < SubscriptionRunner
  end
end

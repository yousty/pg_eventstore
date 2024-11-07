# frozen_string_literal: true

require_relative 'try_to_delete_subscriptions_set'
require_relative 'wait_for_subscriptions_set_shutdown'

module PgEventstore
  module CLI
    class TryUnlockSubscriptionsSet
      class << self
        def try_unlock(...)
          TryToDeleteSubscriptionsSet.try_to_delete(...) || WaitForSubscriptionsSetShutdown.wait_for_shutdown(...)
        end
      end
    end
  end
end

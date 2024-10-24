# frozen_string_literal: true

module PgEventstore
  module CLI
    module Commands
      module CallbackHandlers
        class StartCmdHandlers
          include Extensions::CallbackHandlersExtension

          class << self
            # @param subscription_managers [Array<PgEventstore::SubscriptionsManager>]
            # @param manager [PgEventstore::SubscriptionsManager]
            # @return [void]
            def register_managers(subscription_managers, manager)
              subscription_managers.add(manager)
            end

            # @param action [Proc]
            # @param manager [PgEventstore::SubscriptionsManager]
            # @return [void]
            def handle_start_up(action, manager)
              action.call
            rescue PgEventstore::SubscriptionAlreadyLockedError => error
              PgEventstore.logger&.error(
                <<~TEXT
                  Subscription #{error.name.inspect} from #{error.set.inspect} set is locked under \
                  SubscriptionsSet##{error.lock_id}. Trying to unlock...
                TEXT
              )
              TryUnlockSubscriptionsSet.new(manager.config_name, error.lock_id).try_unlock
              retry
            end
          end
        end
      end
    end
  end
end

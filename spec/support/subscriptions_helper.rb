# frozen_string_literal: true

class SubscriptionsHelper
  class << self
    def create(**attrs)
      defaults = { set: 'FooSet', name: 'FooSubscription' }
      PgEventstore::Subscription.new(
        **PgEventstore::SubscriptionQueries.new(PgEventstore.connection).create(defaults.merge(attrs))
      )
    end

    def create_with_connection(config_name = :default, **attrs)
      PgEventstore::Subscription.using_connection(config_name).new(**create(**attrs).options_hash)
    end
  end
end

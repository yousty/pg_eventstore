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

    def init_with_connection(config_name = :default, **attrs)
      defaults = {
        set: 'FooSet', name: 'FooSubscription', options: {}, max_restarts_number: 0, chunk_query_interval: 1,
        time_between_restarts: 1
      }
      PgEventstore::Subscription.using_connection(config_name).new(**defaults, **attrs)
    end
  end
end

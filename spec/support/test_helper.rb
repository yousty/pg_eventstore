# frozen_string_literal: true

module TestHelper
  def create_subscription(**attrs)
    defaults = { set: 'FooSet', name: 'FooSubscription' }
    PgEventstore::Subscription.new(
      **PgEventstore::SubscriptionQueries.new(PgEventstore.connection).create(defaults.merge(attrs))
    )
  end

  def create_subscriptions_set(**attrs)
    defaults = { name: 'FooSet' }
    PgEventstore::SubscriptionsSet.new(
      **PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection).create(defaults.merge(attrs))
    )
  end
end

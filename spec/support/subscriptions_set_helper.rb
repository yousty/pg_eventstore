# frozen_string_literal: true

class SubscriptionsSetHelper
  class << self
    def create(**attrs)
      defaults = { name: 'FooSet' }
      PgEventstore::SubscriptionsSet.new(
        **PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection).create(defaults.merge(attrs))
      )
    end

    def create_with_connection(config_name = :default, **attrs)
      defaults = { name: 'FooSet' }
      PgEventstore::SubscriptionsSet.using_connection(config_name).new(
        **PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection).create(defaults.merge(attrs))
      )
    end
  end
end

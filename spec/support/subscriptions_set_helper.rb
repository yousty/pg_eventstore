# frozen_string_literal: true

class SubscriptionsSetHelper
  class << self
    def create(**attrs)
      defaults = { name: 'FooSet' }
      PgEventstore::SubscriptionsSet.new(
        **PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection).create(defaults.merge(attrs))
      )
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      class SetCollection
        # @param config [Symbol]
        def initialize(config)
          @config = config
        end

        # @return [Array<String>]
        def names
          @set_collection ||= subscription_queries.set_collection | subscriptions_set_queries.set_names
        end

        private

        # @return [PgEventstore::Connection]
        def connection
          PgEventstore.connection(@config)
        end

        # @return [PgEventstore::SubscriptionQueries]
        def subscription_queries
          SubscriptionQueries.new(connection)
        end

        # @return [PgEventstore::SubscriptionsSetQueries]
        def subscriptions_set_queries
          SubscriptionsSetQueries.new(connection)
        end
      end
    end
  end
end

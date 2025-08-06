# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      class SetCollection
        # @!attribute connection
        #   @return [PgEventstore::Connection]
        attr_reader :connection
        private :connection

        # @param connection [PgEventstore::Connection]
        def initialize(connection)
          @connection = connection
        end

        # @return [Array<String>]
        def names
          @names ||= (subscription_queries.set_collection | subscriptions_set_queries.set_names).sort
        end

        private

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

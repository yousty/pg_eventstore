# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategy
    # @!visibility private
    class Collection < Array
      # This number is used to determine how many subscriptions we fetch per SQL query.
      # @return [Integer]
      DEFAULT_SUBSCRIPTIONS_NUM_PER_QUERY = 10

      class << self
        # @param runners [Array<PgEventstore::SubscriptionRunner>]
        # @param connection [PgEventstore::Connection]
        # @param query_strategy [PgEventstore::QueryStrategy]
        # @param subscriptions_per_query [Integer]
        # @return [PgEventstore::SubscriptionFeedStrategy::Collection]
        def create(runners, connection, query_strategy, subscriptions_per_query: DEFAULT_SUBSCRIPTIONS_NUM_PER_QUERY)
          instance = new
          runners.each_slice(subscriptions_per_query).each do |runners_slice|
            strategy = IndexReadStrategy.new(connection, query_strategy)
            strategy.add(*runners_slice)
            instance.push(strategy)
          end
          instance
        end
      end
    end
  end
end

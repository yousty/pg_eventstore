# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategies
    class Collection
      # This number is used to determine how many subscriptions we fetch per SQL query.
      # @return [Integer]
      DEFAULT_SUBSCRIPTIONS_NUM_PER_QUERY = 10

      class << self
        # @param runners [Array<PgEventstore::SubscriptionRunner>]
        # @param connection [PgEventstore::Connection]
        # @param query_strategy [PgEventstore::QueryStrategy]
        # @param partitions_per_query [Integer]
        # @return [PgEventstore::SubscriptionFeedStrategies::Collection]
        def create(runners, connection, query_strategy, partitions_per_query: DEFAULT_SUBSCRIPTIONS_NUM_PER_QUERY)
          read_groups = runners.each_slice(partitions_per_query).map do |runners_slice|
            strategy = IndexReadStrategy.new(connection, query_strategy)
            strategy.add(*runners_slice)
            strategy
          end
          new.tap do |collection|
            collection.add(*read_groups)
          end
        end
      end

      def initialize
        @collection = []
      end

      def add(*groups)
        @collection.push(*groups)
      end

      def each(...)
        @collection.each(...)
      end
    end
  end
end

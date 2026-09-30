# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategy
    # @!visibility private
    class Collection < Array
      # This number is used to determine how many subscriptions we fetch per SQL query.
      # @return [Integer]
      DEFAULT_SUBSCRIPTIONS_NUM_PER_QUERY = 10

      class << self
        # @param runners_query_options [Hash{PgEventstore::SubscriptionRunner => Hash}]
        # @param connection [PgEventstore::Connection]
        # @param query_strategy [PgEventstore::QueryStrategy]
        # @param subscriptions_per_query [Integer]
        # @return [PgEventstore::SubscriptionFeedStrategy::Collection]
        def create(runners_query_options, connection, query_strategy,
                   subscriptions_per_query: DEFAULT_SUBSCRIPTIONS_NUM_PER_QUERY)
          instance = new
          replica_runners, common_runners = runners_query_options.partition do |runner, _|
            runner.is_a?(ReplicaSubscriptionRunner)
          end
          common_runners.each_slice(subscriptions_per_query) do |runners_slice|
            strategy = IndexReadStrategy.new(connection, query_strategy)
            runners_slice.each { |runner, query_options| strategy.add(runner, query_options) }
            instance.push(strategy)
          end
          replica_runners.each_slice(subscriptions_per_query) do |runners_slice|
            strategy = ReplicationStrategy.new(connection, query_strategy)
            runners_slice.each { |runner, query_options| strategy.add(runner, query_options) }
            instance.push(strategy)
          end
          instance
        end
      end
    end
  end
end

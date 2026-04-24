# frozen_string_literal: true

module PgEventstore
  # This class pulls events from db and feeds given SubscriptionRunners
  # @!visibility private
  class SubscriptionRunnersFeeder
    # @param config_name [Symbol]
    # @param affected_partitions_size_map [PgEventstore::SubscriptionFeedStrategies::AffectedPartitionsSizeMap]
    def initialize(config_name, affected_partitions_size_map)
      @config_name = config_name
      @affected_partitions_size_map = affected_partitions_size_map
    end

    # @param runners [Array<PgEventstore::SubscriptionRunner>]
    # @return [void]
    def feed(runners)
      runners = runners.select(&:running?).select(&:time_to_feed?)
      return if runners.empty?

      feed_strategies_collection = SubscriptionFeedStrategies::Collection.create(
        runners,
        @affected_partitions_size_map,
        connection,
        QueryStrategy::Async.new(connection)
      )
      safe_position = subscription_service_queries.safe_global_position
      query_runner = AsyncQueryRunner.new
      feed_strategies_collection.each do |strategy|
        query_runner.async do
          strategy.feed(safe_position)
        end
      end
      query_runner.run
    end

    private

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(@config_name)
    end

    # @return [PgEventstore::SubscriptionServiceQueries]
    def subscription_service_queries
      SubscriptionServiceQueries.new(connection)
    end
  end
end

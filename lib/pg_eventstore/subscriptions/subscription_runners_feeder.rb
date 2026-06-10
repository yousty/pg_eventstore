# frozen_string_literal: true

module PgEventstore
  # This class pulls events from db and feeds given SubscriptionRunners
  # @!visibility private
  class SubscriptionRunnersFeeder
    # @param config_name [Symbol]
    def initialize(config_name)
      @config_name = config_name
    end

    # @param runners [Array<PgEventstore::SubscriptionRunner>]
    # @return [void]
    def feed(runners)
      runners = runners.select(&:running?).select(&:time_to_feed?)
      return if runners.empty?

      feed_strategies_collection = SubscriptionFeedStrategy::Collection.create(
        runners,
        connection,
        QueryStrategy::Async.new(connection)
      )
      query_runner = AsyncQueryRunner.new
      feed_strategies_collection.each do |strategy|
        query_runner.async { strategy.feed }
      end
      query_runner.run
    end

    private

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(@config_name)
    end
  end
end

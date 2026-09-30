# frozen_string_literal: true

module PgEventstore
  # This class decides which SubscriptionRunners to feed, pulls events from db and feeds them
  # @!visibility private
  class SubscriptionRunnersFeeder
    # @param config_name [Symbol]
    def initialize(config_name)
      @config_name = config_name
    end

    # @param runners [Array<PgEventstore::SubscriptionRunner>]
    # @return [void]
    def feed(runners)
      runners_query_options = runners.select { |runner| runner.running? && time_to_feed?(runner) }.to_h do |runner|
        [runner, runner.next_chunk_query_opts]
      end
      # A runner which has enough events in its queue estimates the number of events to fetch to 0
      runners_query_options = runners_query_options.select { |_, query_options| query_options[:max_count] > 0 }
      return if runners_query_options.empty?

      feed_strategies_collection = SubscriptionFeedStrategy::Collection.create(
        runners_query_options,
        connection,
        QueryStrategy::Async.new(connection)
      )
      query_runner = AsyncRunner.new
      feed_strategies_collection.each do |strategy|
        query_runner.async { strategy.feed }
      end
      query_runner.run
    end

    private

    # @param runner [PgEventstore::SubscriptionRunner]
    # @return [Boolean]
    def time_to_feed?(runner)
      subscription = runner.subscription
      subscription.last_chunk_fed_at + subscription.chunk_query_interval <= Time.now.utc
    end

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(@config_name)
    end
  end
end

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

      runners_query_options = runners.to_h { |runner| [runner.id, runner.next_chunk_query_opts] }
      grouped_events = subscription_queries.subscriptions_events(runners_query_options)

      runners.each do |runner|
        runner.feed(grouped_events[runner.id]) if grouped_events[runner.id]
      end
    end

    private

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(@config_name)
    end

    # @return [PgEventstore::SubscriptionQueries]
    def subscription_queries
      SubscriptionQueries.new(connection)
    end
  end
end

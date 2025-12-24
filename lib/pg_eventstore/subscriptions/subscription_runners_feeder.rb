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

      safe_pos = subscription_service_queries.smallest_uncommitted_global_position(current_database_id)
      runners_query_options = runners.to_h do |runner|
        [runner.id, runner.next_chunk_query_opts.merge(to_position: safe_pos)]
      end
      grouped_events = subscription_queries.subscriptions_events(runners_query_options)

      runners.each do |runner|
        runner.feed(grouped_events[runner.id]) if grouped_events[runner.id]
      end
    end

    private

    # @return [Integer]
    def current_database_id
      @current_database_id ||= subscription_service_queries.current_database_id
    end

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(@config_name)
    end

    # @return [PgEventstore::SubscriptionQueries]
    def subscription_queries
      SubscriptionQueries.new(connection)
    end

    # @return [PgEventstore::SubscriptionServiceQueries]
    def subscription_service_queries
      SubscriptionServiceQueries.new(connection)
    end
  end
end

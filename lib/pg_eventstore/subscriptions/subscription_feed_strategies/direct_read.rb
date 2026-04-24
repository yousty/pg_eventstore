# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategies
    class DirectRead
      include SubscriptionFeedStrategies

      def initialize(connection, query_strategy)
        @connection = connection
        @query_strategy = query_strategy
        @runners = []
      end

      def add(runner)
        @runners.push(runner)
      end

      def size
        @runners.size
      end

      def any?
        @runners.any?
      end

      def feed(safe_position)
        runners_query_options = @runners.to_h do |runner|
          [runner.id, runner.next_chunk_query_opts.merge(to_position: safe_position)]
        end
        grouped_events = subscription_queries.subscriptions_events(runners_query_options)
        @runners.each do |runner|
          if grouped_events[runner.id]
            runner.feed(RawEntities::EventsChunk.new(grouped_events[runner.id]))
          else
            runner.checkpoint(safe_position)
          end
        end
      end

      private

      # @return [PgEventstore::SubscriptionQueries]
      def subscription_queries
        SubscriptionQueries.new(@connection, @query_strategy)
      end
    end
  end
end

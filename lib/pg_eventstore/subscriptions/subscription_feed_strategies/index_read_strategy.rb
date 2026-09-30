# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategy
    # @!visibility private
    class IndexReadStrategy
      include SubscriptionFeedStrategy

      # Allow subscriptions to scan through up to this amount of events per a single query. This allows to make query
      # plan more predictable. Downside: let's say subscription1 targets "Foo" event type, but between
      # SubscriptionRunnersFeeder#feed runs more than this amount of events other than "Foo" event type are published -
      # it will require at least one more loop to pick that event.
      # @return [Integer]
      INDEX_LOOK_UP_DISTANCE = 100_000

      # @param connection [PgEventstore::Connection]
      # @param query_strategy [PgEventstore::QueryStrategy]
      def initialize(connection, query_strategy)
        @connection = connection
        @query_strategy = query_strategy
        @runners_query_options = {}
      end

      # @param runner [PgEventstore::SubscriptionRunner]
      # @param query_options [Hash]
      # @return [void]
      def add(runner, query_options)
        @runners_query_options[runner] = query_options
      end

      # @return [Integer]
      def size
        @runners_query_options.size
      end

      # @return [Boolean]
      def any?
        @runners_query_options.any?
      end

      # @return [void]
      def feed
        @runners_query_options.each_value do |query_options|
          query_options[:to_position] = [query_options[:from_position] + INDEX_LOOK_UP_DISTANCE, safe_position].min
        end
        grouped_indexes = events_global_index_queries.fetch_indexes_for_subscriptions(
          @runners_query_options.transform_keys(&:id)
        )
        @runners_query_options.each do |runner, query_options|
          if grouped_indexes[runner.id]
            chunk = Chunks::SubscriptionEventsIndexChunk.new(
              grouped_indexes[runner.id],
              @connection,
              QueryStrategy::Foreground.new(@connection),
              query_options[:resolve_link_tos]
            )
            runner.feed(chunk)
          else
            runner.feed(Chunks::SubscriptionCheckpointChunk.new(query_options[:to_position]))
          end
        end
      end

      private

      # @return [Integer]
      def safe_position
        event_subscription_position_queries.max_subscription_position || 0
      end

      # @return [PgEventstore::EventsGlobalIndexQueries]
      def events_global_index_queries
        EventsGlobalIndexQueries.new(@connection, @query_strategy)
      end

      # @return [PgEventstore::EventSubscriptionPositionQueries]
      def event_subscription_position_queries
        EventSubscriptionPositionQueries.new(@connection)
      end
    end
  end
end

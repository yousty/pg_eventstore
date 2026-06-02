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
        @runners = []
      end

      # @param runners [Array<PgEventstore::SubscriptionRunner>]
      # @return [Array<PgEventstore::SubscriptionRunner>]
      def add(*runners)
        @runners.push(*runners)
      end

      # @return [Integer]
      def size
        @runners.size
      end

      # @return [Boolean]
      def any?
        @runners.any?
      end

      # @param safe_position [Integer]
      # @return [void]
      def feed(safe_position)
        runners_query_options = @runners.to_h do |runner|
          next_chunk_query_opts = runner.next_chunk_query_opts
          next_chunk_query_opts[:to_position] =
            [next_chunk_query_opts[:from_position] + INDEX_LOOK_UP_DISTANCE, safe_position].min
          [runner.id, next_chunk_query_opts]
        end
        grouped_indexes = events_global_index_queries.fetch_indexes_for_subscriptions(runners_query_options)
        @runners.each do |runner|
          if grouped_indexes[runner.id]
            chunk = Chunks::EventsIndexChunk.new(
              grouped_indexes[runner.id],
              @connection,
              QueryStrategy::Foreground.new(@connection),
              runners_query_options[runner.id][:resolve_link_tos]
            )
            runner.feed(chunk)
          else
            runner.checkpoint(runners_query_options[runner.id][:to_position])
          end
        end
      end

      private

      # @return [PgEventstore::EventsGlobalIndexQueries]
      def events_global_index_queries
        EventsGlobalIndexQueries.new(@connection, @query_strategy)
      end
    end
  end
end

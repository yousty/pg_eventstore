# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategy
    # @!visibility private
    class ReplicationStrategy
      include SubscriptionFeedStrategy

      # Allow subscriptions to scan through up to this amount of events per a single query. This allows to make query
      # plan more predictable.
      # @return [Integer]
      INDEX_LOOK_UP_DISTANCE = 100_000

      # @param connection [PgEventstore::Connection]
      # @param query_strategy [PgEventstore::QueryStrategy]
      def initialize(connection, query_strategy)
        @connection = connection
        @query_strategy = query_strategy
        @runners = []
      end

      # @param runners [Array<PgEventstore::ReplicaSubscriptionRunner>]
      # @return [Array<PgEventstore::ReplicaSubscriptionRunner>]
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

      # @return [void]
      def feed
        # One query instead of one per runner. A slightly stale value is at least as safe as a fresh one.
        max_to_position = safe_position
        runners_query_options = @runners.to_h do |runner|
          next_chunk_query_opts = runner.next_chunk_query_opts
          next_chunk_query_opts[:to_position] =
            [next_chunk_query_opts[:from_position] + INDEX_LOOK_UP_DISTANCE, max_to_position].min
          [runner.id, next_chunk_query_opts]
        end
        # By now the runner may estimate 0 events to fetch - its queue is processed in another thread. A query with
        # zero limit returns nothing, and we can't tell that from the absence of matching events in the range.
        # Checkpointing such runner would skip its events, so leave it until the next feed instead.
        runners_query_options = runners_query_options.select { |_, query_options| query_options[:max_count] > 0 }
        return if runners_query_options.empty?

        grouped_indexes = events_global_index_queries.fetch_indexes_for_subscriptions(runners_query_options)
        @runners.each do |runner|
          next unless runners_query_options.key?(runner.id)

          if grouped_indexes[runner.id]
            chunk = Chunks::ReplicaEventsIndexChunk.new(grouped_indexes[runner.id])
            runner.feed(chunk)
          else
            runner.feed(Chunks::SubscriptionCheckpointChunk.new(runners_query_options[runner.id][:to_position]))
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

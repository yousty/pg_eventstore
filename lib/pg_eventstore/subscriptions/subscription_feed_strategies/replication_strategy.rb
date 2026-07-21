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
        runners_query_options = @runners.to_h do |runner|
          next_chunk_query_opts = runner.next_chunk_query_opts
          next_chunk_query_opts[:to_position] =
            [next_chunk_query_opts[:from_position] + INDEX_LOOK_UP_DISTANCE, safe_position].min
          [runner.id, next_chunk_query_opts]
        end
        grouped_indexes = events_global_index_queries.fetch_indexes_for_subscriptions(runners_query_options)
        @runners.each do |runner|
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

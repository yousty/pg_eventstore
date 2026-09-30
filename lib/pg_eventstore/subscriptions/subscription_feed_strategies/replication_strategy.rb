# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategy
    # @!visibility private
    class ReplicationStrategy
      include SubscriptionFeedStrategy

      # @param connection [PgEventstore::Connection]
      # @param query_strategy [PgEventstore::QueryStrategy]
      def initialize(connection, query_strategy)
        @connection = connection
        @query_strategy = query_strategy
        @runners_query_options = {}
      end

      # @param runner [PgEventstore::ReplicaSubscriptionRunner]
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
        grouped_indexes = events_global_index_queries.fetch_indexes_for_subscriptions(
          @runners_query_options.transform_keys(&:id)
        )
        @runners_query_options.each do |runner, query_options|
          if grouped_indexes[runner.id]
            chunk = Chunks::ReplicaEventsIndexChunk.new(grouped_indexes[runner.id])
            runner.feed(chunk)
          else
            runner.feed(Chunks::SubscriptionCheckpointChunk.new(query_options[:to_position]))
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

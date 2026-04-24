# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeedStrategies
    class IndexRead
      include SubscriptionFeedStrategies

      # Allow large subscriptions(querying among more than SubscriptionRunnersFeeder::MAX_PARTITIONS_PER_QUERY
      # partitions) to scan through up to this amount of events per a single query. This allows to make query plan more
      # predictable. Downside: let's say subscription1 targets "Foo" event type, but between
      # SubscriptionRunnersFeeder#feed runs more than this amount of events other than "Foo" event type are published -
      # it will require at least one more loop to pick that event.
      # @return [Integer]
      INDEX_LOOK_UP_DISTANCE = 100_000

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
          next_chunk_query_opts = runner.next_chunk_query_opts
          next_chunk_query_opts[:to_position] =
            [next_chunk_query_opts[:from_position] + INDEX_LOOK_UP_DISTANCE, safe_position].min
          [runner.id, next_chunk_query_opts]
        end
        grouped_indexes = events_global_index_queries.grouped_indexes(runners_query_options)
        @runners.each do |runner|
          if grouped_indexes[runner.id]
            runner.feed(RawEntities::EventIndexesChunk.new(grouped_indexes[runner.id], @connection))
          else
            runner.checkpoint(runners_query_options[runner.id][:to_position])
          end
        end
      end

      private

      def events_global_index_queries
        EventsGlobalIndexQueries.new(@connection, @query_strategy)
      end
    end
  end
end

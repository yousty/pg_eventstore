# frozen_string_literal: true

module PgEventstore
  module RawEntities
    class EventIndexesChunk
      include Chunk

      MAX_PARTITIONS_TO_RESOLVE_PER_CALL = 50

      def initialize(indexes, connection)
        @indexes = indexes
        @events = []
        @last_global_position = Utils.original_global_position(indexes.last)
        @connection = connection
        @resolved = false
      end

      def take(size)
        resolve_indexes unless resolved?
        @events.slice!(0...size)
      end

      def empty?
        @indexes.empty? && @events.empty?
      end

      def last_global_position
        @last_global_position
      end

      def size
        @indexes.size + @events.size
      end

      private

      # @return [Boolean]
      def resolved?
        @resolved
      end

      # @return [void]
      def resolve_indexes
        indexes_to_resolve = @indexes.slice!(range_to_slice)
        raw_events = events_global_index_queries.resolve_indexes(indexes_to_resolve)
        @events.push(*raw_events)
        @resolved = @indexes.empty?
      rescue => exception
        @indexes.unshift(*indexes_to_resolve)
        @resolved = false
        raise Utils.wrap_exception(
          exception, global_positions: indexes_to_resolve.map(&Utils.method(:original_global_position))
        )
      end

      # @return [Range]
      def range_to_slice
        return (0..) if @indexes.size <= MAX_PARTITIONS_TO_RESOLVE_PER_CALL

        partitions_map = Set.new
        latest_index = 0
        @indexes.each_with_index do |events_index, index|
          partitions_map.add(events_index['partition_id'])
          latest_index = index
          break if partitions_map.size == MAX_PARTITIONS_TO_RESOLVE_PER_CALL
        end
        0..latest_index
      end

      def events_global_index_queries
        EventsGlobalIndexQueries.new(@connection, QueryStrategy::Foreground.new(@connection))
      end
    end
  end
end

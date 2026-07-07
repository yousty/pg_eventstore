# frozen_string_literal: true

module PgEventstore
  module Chunks
    # @!visibility private
    class ReadApiEventsIndexChunk
      include Chunk

      # @return [Integer]
      MAX_PARTITIONS_TO_RESOLVE_PER_CALL = 100

      # @param indexes [Array<PgEventstore::EventGlobalIndex::ReadApiRepr>]
      # @param connection [PgEventstore::Connection]
      # @param query_strategy [PgEventstore::QueryStrategy]
      # @param resolve_link_tos [Boolean]
      def initialize(indexes, connection, query_strategy, resolve_link_tos)
        @indexes = indexes
        @connection = connection
        @query_strategy = query_strategy
        @resolve_link_tos = resolve_link_tos
        @idx_direction = detect_direction(indexes[0], indexes[1])
        @raw_events = []
        @resolved = indexes.empty?
      end

      # @return [Array<Hash>] raw events array
      def take(size)
        resolve_indexes unless resolved?
        @raw_events.slice!(0...size)
      end

      # @return [Boolean]
      def drained?
        @indexes.empty? && @raw_events.empty?
      end

      # @return [Integer]
      def size
        @indexes.size + @raw_events.size
      end

      # @return [PgEventstore::EventGlobalIndex::ReadApiRepr, nil]
      def last
        @indexes.last
      end

      private

      # @param idx1 [PgEventstore::EventGlobalIndex::ReadApiRepr, nil]
      # @param idx2 [PgEventstore::EventGlobalIndex::ReadApiRepr, nil]
      # @return [Symbol]
      def detect_direction(idx1, idx2)
        return :asc if idx1.nil? || idx2.nil?

        idx1.global_position > idx2.global_position ? :desc : :asc
      end

      # @return [Boolean]
      def resolved?
        @resolved
      end

      # @return [void]
      def resolve_indexes
        indexes_to_resolve = @indexes.slice!(
          range_to_slice(@indexes.map(&:event_type_partition_id), MAX_PARTITIONS_TO_RESOLVE_PER_CALL)
        )
        raw_events = events_global_index_queries.resolve_indexes(
          indexes_to_resolve,
          direction: @idx_direction,
          resolve_link_tos: @resolve_link_tos
        )
        @raw_events.push(*raw_events)
        @resolved = @indexes.empty?
      end

      # @return [PgEventstore::EventsGlobalIndexQueries]
      def events_global_index_queries
        EventsGlobalIndexQueries.new(@connection, @query_strategy)
      end
    end
  end
end

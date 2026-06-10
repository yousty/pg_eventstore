# frozen_string_literal: true

module PgEventstore
  module Chunks
    # @!visibility private
    class SubscriptionEventsIndexChunk
      include Chunk

      class RawEventWithCommitPosition
        include Extensions::OptionsExtension
        include Extensions::OptionsDefaults

        # @!attribute subscription_position
        #   @return [Integer]
        attribute(:subscription_position)
        # @!attribute attributes
        #   @return [Hash<String, Object>]
        attribute(:attributes)
      end

      # @return [Integer]
      MAX_PARTITIONS_TO_RESOLVE_PER_CALL = 100

      # @param indexes [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
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

      # @return [Array<RawEventWithCommitPosition>] raw events array
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

      # @return [PgEventstore::EventGlobalIndex::SubscriptionRepr, nil]
      def last
        @indexes.last
      end

      private

      # @param idx1 [PgEventstore::EventGlobalIndex::SubscriptionRepr, nil]
      # @param idx2 [PgEventstore::EventGlobalIndex::SubscriptionRepr, nil]
      # @return [Symbol]
      def detect_direction(idx1, idx2)
        return :asc if idx1.nil? || idx2.nil?

        idx1.subscription_position > idx2.subscription_position ? :desc : :asc
      end

      # @return [Boolean]
      def resolved?
        @resolved
      end

      # @return [void]
      def resolve_indexes
        indexes_to_resolve = @indexes.slice!(range_to_slice)
        global_to_sub_position_map = indexes_to_resolve.to_h { [_1.global_position, _1.subscription_position] }
        raw_events = events_global_index_queries.resolve_indexes(
          indexes_to_resolve,
          resolve_link_tos: @resolve_link_tos
        )
        raw_events = raw_events.map do |attrs|
          global_position = attrs['link'] ? attrs['link']['global_position'] : attrs['global_position']
          RawEventWithCommitPosition.new(
            attributes: attrs,
            subscription_position: global_to_sub_position_map[global_position]
          )
        end
        raw_events = sort(raw_events)
        @raw_events.push(*raw_events)
        @resolved = @indexes.empty?
      rescue => exception
        @indexes.unshift(*indexes_to_resolve)
        @resolved = false
        raise Utils.wrap_exception(
          exception, global_positions: indexes_to_resolve.map(&:global_position)
        )
      end

      # @return [Range]
      def range_to_slice
        return (0..) if @indexes.size <= MAX_PARTITIONS_TO_RESOLVE_PER_CALL

        partitions_map = {}
        latest_index = nil
        @indexes.each_with_index do |events_index, index|
          partitions_map[events_index.event_type_partition_id] = true
          if partitions_map.size > MAX_PARTITIONS_TO_RESOLVE_PER_CALL
            latest_index = index - 1
            break
          end
        end
        0..latest_index
      end

      # @param raw_events [Array<RawEventWithCommitPosition>]
      # @return [Array<RawEventWithCommitPosition>]
      def sort(raw_events)
        if @idx_direction == :asc
          raw_events.sort_by(&:subscription_position)
        else
          raw_events.sort_by { |e1, e2| e2.subscription_position <=> e1.subscription_position }
        end
      end

      # @return [PgEventstore::EventsGlobalIndexQueries]
      def events_global_index_queries
        EventsGlobalIndexQueries.new(@connection, @query_strategy)
      end
    end
  end
end

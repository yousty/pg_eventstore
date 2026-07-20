# frozen_string_literal: true

module PgEventstore
  module Chunks
    # @!visibility private
    class ReplicaEventsIndexChunk
      include Chunk

      # @param indexes [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
      def initialize(indexes)
        @indexes = indexes
      end

      # @return [Array<RawEventWithSubscriptionPosition>] raw events array
      def take(size)
        @indexes.slice!(0...size)
      end

      # @return [Boolean]
      def drained?
        @indexes.empty?
      end

      # @return [Integer]
      def size
        @indexes.size
      end

      # @return [PgEventstore::EventGlobalIndex::SubscriptionRepr, nil]
      def last
        @indexes.last
      end
    end
  end
end

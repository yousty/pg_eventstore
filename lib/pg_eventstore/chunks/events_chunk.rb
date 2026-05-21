# frozen_string_literal: true

module PgEventstore
  module Chunks
    class EventsChunk
      include Chunk

      def initialize(events)
        @events = events
        @last_global_position = Utils.original_global_position(events.last) if events.any?
      end

      def take(size)
        @events.slice!(0...size)
      end

      def empty?
        @events.empty?
      end

      def last_global_position
        @last_global_position
      end

      def size
        @events.size
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  module Chunks
    # @!visibility private
    class SubscriptionCheckpointChunk
      include Chunk

      class Checkpoint
        include Extensions::OptionsExtension
        include Extensions::OptionsDefaults

        # @!attribute subscription_position
        #   @return [Integer]
        attribute(:subscription_position)
      end

      # @param position [Integer]
      def initialize(position)
        @checkpoint_event = Checkpoint.new(subscription_position: position)
      end

      def take(_size)
        if @checkpoint_event
          event = @checkpoint_event
          @checkpoint_event = nil
          return [event]
        end
        []
      end

      # @return [Boolean]
      def drained?
        @checkpoint_event.nil?
      end

      # @return [Integer]
      def size
        @checkpoint_event ? 1 : 0
      end

      # @return [Object, nil]
      def last
        @checkpoint_event
      end
    end
  end
end

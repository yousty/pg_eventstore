# frozen_string_literal: true

module PgEventstore
  module Chunks
    # @!visibility private
    module Chunk
      # @param size [Integer, nil] number of entities to retrieve. nil means all available. The number of entities in
      #   the result in the single call is not guaranteed. You have to check whether chunk is drained using #drained? in
      #   a subsequent call.
      # @return [Array]
      def take(size)
        raise NotImplementedError
      end

      # @return [Boolean]
      def drained?
        raise NotImplementedError
      end

      # @return [Integer]
      def size
        raise NotImplementedError
      end

      # @return [Object, nil]
      def last
        raise NotImplementedError
      end
    end
  end
end

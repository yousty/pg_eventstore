# frozen_string_literal: true

module PgEventstore
  module Chunks
    module Chunk
      # @param size [Integer, nil]
      def take(size)
        raise NotImplementedError
      end

      def empty?
        raise NotImplementedError
      end

      def last_global_position
        raise NotImplementedError
      end

      def size
        raise NotImplementedError
      end
    end
  end
end


# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class ReadStreams < AbstractCommand
      # @param options [Hash] request options
      # @option options [String] :direction
      # @option options [Integer] :from_position
      # @option options [Integer] :max_count
      # @return [Array<PgEventstore::Stream>]
      def call(options: {})
        indexes = queries.streams_global_index.streams_global_index(options)
        queries.streams_global_index.resolve_indexes(indexes)
      end
    end
  end
end

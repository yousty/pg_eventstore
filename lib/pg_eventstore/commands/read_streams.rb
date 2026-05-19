# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class ReadStreams < AbstractCommand
      # @return [Array<PgEventstore::Stream>]
      def call(options: {})
        indexes = queries.streams_global_index.streams_global_index(options)
        queries.streams_global_index.resolve_indexes(indexes)
      end
    end
  end
end

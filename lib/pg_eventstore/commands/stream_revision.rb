# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class StreamRevision < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @return [Integer]
      def call(stream)
        queries.streams_global_index.stream_revision(stream) || Stream::NON_EXISTING_STREAM_REVISION
      end
    end
  end
end

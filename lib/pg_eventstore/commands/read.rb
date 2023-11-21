# frozen_string_literal: true

module PgEventstore
  module Commands
    class Read < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @param options [Hash] request options
      # @option options [String] :direction read direction - 'Forwards' or 'Backwards'
      # @option options [Integer, Symbol] :from_revision. **Use this option when stream name is a normal stream name**
      # @option options [Integer, Symbol] :from_position. **Use this option when reading from "all" stream**
      # @option options [Integer] :max_count
      # @option options [Boolean] :resolve_link_tos
      # @option options [Hash] :filter provide it to filter events
      # @return [Array<PgEventstore::Event>]
      # @raise [PgEventstore::StreamNotFoundError]
      def call(stream, options: {})
        queries.last_stream_event(stream) || raise(StreamNotFoundError, stream) unless stream.all_stream?

        queries.stream_events(stream, options)
      end
    end
  end
end

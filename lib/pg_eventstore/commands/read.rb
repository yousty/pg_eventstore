# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class Read < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @param deserializer [PgEventstore::EventDeserializer]
      # @param options [Hash] request options
      # @option options [String] :direction read direction - 'Forwards' or 'Backwards'
      # @option options [Integer] :from_revision. **Use this option when stream is a regular stream**
      # @option options [Integer] :from_position. **Use this option when reading from "all" stream**
      # @option options [Integer] :to_revision. **Use this option when stream is a regular stream**
      # @option options [Integer] :to_position. **Use this option when reading from "all" stream**
      # @option options [Integer] :max_count
      # @option options [Boolean] :resolve_link_tos
      # @option options [Hash] :filter provide it to filter events
      # @return [Array<PgEventstore::Event>]
      # @raise [PgEventstore::StreamNotFoundError]
      def call(stream, deserializer:, options: {})
        queries.streams_global_index.stream_exists?(stream) || raise(StreamNotFoundError, stream) unless stream.system?

        filter_collection = QueryBuilders::Filters::Collection.from_stream_and_options(stream, options)
        cursor = QueryBuilders::ReadCursor::StreamCursor.from_stream_and_options(stream, options)
        raise NotSupportedError, '#read does not support look up by prefix.' if filter_collection.has_prefix_filter?

        indexes = queries.events_global_index.fetch_indexes_for_read_api(filter_collection, cursor)
        repo = queries.events_global_index.compute_read_api_chunks_repo(indexes, options[:resolve_link_tos] || false)
        deserializer.deserialize_many(repo.consume_all)
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class RegularStreamReadGrouped < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @param options [Hash] request options
      # @option options [String] :direction read direction
      # @option options [Integer, Symbol] :from_revision. **Use this option when stream name is a normal stream name**
      # @option options [Integer, Symbol] :from_position. **Use this option when reading from "all" stream**
      # @option options [Boolean] :resolve_link_tos
      # @option options [Hash] :filter provide it to filter events
      # @return [Array<PgEventstore::Event>]
      # @raise [PgEventstore::StreamNotFoundError]
      def call(stream, options: {})
        queries.events.stream_revision(stream) || raise(StreamNotFoundError, stream)

        event_types = QueryBuilders::PartitionsFiltering.extract_event_types_filter(options)
        stream_filters = QueryBuilders::PartitionsFiltering.extract_streams_filter(
          filter: { streams: [{ context: stream.context, stream_name: stream.stream_name }] }
        )
        options_by_event_type = queries.partitions.partitions(stream_filters, event_types).map do |partition|
          filter = { event_types: [partition.event_type] }
          options.merge(filter:, max_count: 1)
        end
        queries.events.grouped_events(stream, options_by_event_type, **options.slice(:resolve_link_tos))
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class AllStreamReadGrouped < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @param options [Hash] request options
      # @option options [String] :direction read direction
      # @option options [Integer, Symbol] :from_position. **Use this option when reading from "all" stream**
      # @option options [Boolean] :resolve_link_tos
      # @option options [Hash] :filter provide it to filter events
      # @return [Array<PgEventstore::Event>]
      # @raise [PgEventstore::StreamNotFoundError]
      def call(stream, options: {})
        event_types = QueryBuilders::PartitionsFiltering.extract_event_types_filter(options)
        stream_filters = QueryBuilders::PartitionsFiltering.extract_streams_filter(options)
        stream_ids_grouped = group_stream_ids(options)
        options_by_event_type =
          queries.partitions.partitions(stream_filters, event_types).flat_map do |partition|
            stream_ids = stream_ids_grouped[[partition.context, partition.stream_name]]
            next build_filter_options_for_streams(partition, stream_ids, options) if stream_ids

            build_filter_options_for_partitions(partition, options)
          end
        queries.events.grouped_events(stream, options_by_event_type, **options.slice(:resolve_link_tos))
      end

      private

      # @param options [Hash]
      # @return [Hash]
      def group_stream_ids(options)
        event_stream_filters = QueryBuilders::EventsFiltering.extract_streams_filter(options)
        event_stream_filters.each_with_object({}) do |attrs, res|
          next unless attrs[:stream_id]

          res[[attrs[:context], attrs[:stream_name]]] ||= []
          res[[attrs[:context], attrs[:stream_name]]].push(attrs[:stream_id])
        end
      end

      # @param partition [PgEventstore::Partition]
      # @param stream_ids [Array<String>]
      # @param options [Hash]
      # @return [Array<Hash>]
      def build_filter_options_for_streams(partition, stream_ids, options)
        stream_ids.map do |stream_id|
          filter = {
            streams: [{ context: partition.context, stream_name: partition.stream_name, stream_id: }],
            event_types: [partition.event_type],
          }
          options.merge(filter:, max_count: 1)
        end
      end

      # @param partition [PgEventstore::Partition]
      # @param options [Hash]
      # @return [Hash]
      def build_filter_options_for_partitions(partition, options)
        filter = {
          streams: [{ context: partition.context, stream_name: partition.stream_name }],
          event_types: [partition.event_type],
        }
        options.merge(filter:, max_count: 1)
      end
    end
  end
end

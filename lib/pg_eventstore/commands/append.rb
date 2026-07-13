# frozen_string_literal: true

require_relative 'revision_check/stream_revision_check'

module PgEventstore
  module Commands
    # @!visibility private
    class Append < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @param events [Array<PgEventstore::Event>]
      # @param event_modifier [#call]
      # @param deserializer [PgEventstore::EventDeserializer]
      # @param options [Hash]
      # @option options [Integer] :expected_revision provide your own revision number
      # @option options [Symbol] :expected_revision provide one of next values: :any, :no_stream or :stream_exists
      # @return [Array<PgEventstore::Event>] persisted events
      # @raise [PgEventstore::WrongExpectedRevisionError]
      def call(stream, *events, event_modifier:, deserializer:, options: {})
        raise SystemStreamError, stream if stream.system?
        raise ArgumentError, 'No events to append.' if events.empty?

        events = events.map(&event_modifier.method(:call))
        markers = events.flat_map { _1.markers + feature_markers(_1) }.uniq
        raw_events = queries.transactions.transaction(:repeatable_read) do
          revision_to_marker_ids_map = {}
          partitions = prepare_partitions(stream, events)
          stream_index = queries.streams_global_index.find_or_create_by(stream)
          markers_map = queries.event_markers.find_or_create_by(markers).to_h { [_1.name, _1.id] } if markers.any?
          revision = stream_index.stream_revision
          expected_revision = RevisionCheck::ExpectedRevision.build(options[:expected_revision])
          current_revision = RevisionCheck::CurrentRevision.build(
            stream, revision, expected_revision, queries.index_filtering
          )
          RevisionCheck::StreamRevisionCheck.assert_eq!(current_revision, expected_revision, stream)
          events.each.with_index(1) do |event, index|
            event.stream_revision = revision + index
            event.markers.each do |event_marker|
              revision_to_marker_ids_map[revision + index] ||= []
              revision_to_marker_ids_map[revision + index].push(markers_map[event_marker])
            end
            event.feature_markers.each do |feature_marker|
              revision_to_marker_ids_map[revision + index] ||= []
              revision_to_marker_ids_map[revision + index].push(markers_map[feature_marker.marker])
            end
          end
          revision += events.size
          queries.events.insert(stream, events).tap do |created_events|
            stream_idx_attrs_to_update = { stream_revision: revision }
            if stream_index.starting_position == StreamGlobalIndex::INITIAL_STARTING_POSITION
              stream_idx_attrs_to_update[:starting_position] = created_events.first['global_position']
            end
            queries.streams_global_index.update(stream_index.id, **stream_idx_attrs_to_update)
            write_api_events_idx = queries.events_global_index.index_events(created_events, partitions, stream_index.id)
            queries.event_subscription_positions.create_unprocessed_positions(created_events)
            if markers.any?
              queries.event_markers.create_indexes(
                stream_index.id, write_api_events_idx, revision_to_marker_ids_map
              )
            end
          end
        end
        # It is important to return events in the form they were persisted into the database instead passing them
        # through the configured middlewares
        deserializer.deserialize_many(raw_events)
      end

      private

      # @param event [PgEventstore::Event]
      # @return [Array<String>]
      def feature_markers(event)
        event.feature_markers.map(&:marker)
      end

      # @param stream [PgEventstore::Stream]
      # @param events [Array<PgEventstore::Event>]
      # @return [Array<PgEventstore::Partition>]
      def prepare_partitions(stream, events)
        event_types = events.map { _1.type.to_s }.uniq
        filter_collection = QueryBuilders::Filters::Collection.from_options(
          { filter: { streams: [{ context: stream.context, stream_name: stream.stream_name }], event_types: } }
        )
        existing_partitions = queries.partitions.partitions(filter_collection)
        missing_event_types = event_types - existing_partitions.map(&:event_type)
        raise MissingPartitions.new(stream, missing_event_types) if missing_event_types.any?

        existing_partitions
      end
    end
  end
end

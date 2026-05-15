# frozen_string_literal: true

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
        raise ArgumentError, 'No events to append' if events.empty?

        events = events.map(&event_modifier.method(:call))
        raw_events = queries.transactions.transaction(:repeatable_read) do
          partitions = prepare_partitions(stream, events)
          stream_index = queries.streams_global_index.find_or_create_by(stream)
          revision = stream_index.stream_revision
          assert_expected_revision!(revision, options[:expected_revision], stream) if options[:expected_revision]
          events.each.with_index(1) do |event, index|
            event.stream_revision = revision + index
          end
          revision += events.size
          queries.events.insert(stream, events).tap do |created_events|
            stream_idx_attrs_to_update = { stream_revision: revision }
            if stream_index.starting_position == StreamGlobalIndex::INITIAL_STARTING_POSITION
              stream_idx_attrs_to_update[:starting_position] = created_events.first['global_position']
            end
            queries.streams_global_index.update(stream_index.id, **stream_idx_attrs_to_update)
            queries.events_global_index.index_events(created_events, partitions, stream_index.id)
          end
        end
        # It is important to return events in the form they were persisted into the database instead deserializing them
        # using configured middlewares
        deserializer.without_middlewares.deserialize_many(raw_events)
      end

      private

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

      # @param revision [Integer]
      # @param expected_revision [Symbol, Integer]
      # @param stream [PgEventstore::Stream]
      # @raise [PgEventstore::WrongExpectedRevisionError] in case if revision does not satisfy expected revision
      # @return [void]
      def assert_expected_revision!(revision, expected_revision, stream)
        return if expected_revision == :any

        case [revision, expected_revision]
        in [Integer, Integer]
          unless revision == expected_revision
            raise WrongExpectedRevisionError.new(
              revision:, expected_revision:, stream:
            )
          end

        in [Integer, Symbol]
          if revision == Stream::NON_EXISTING_STREAM_REVISION && expected_revision == :stream_exists
            raise WrongExpectedRevisionError.new(
              revision:, expected_revision:, stream:
            )
          end
          if revision > Stream::NON_EXISTING_STREAM_REVISION && expected_revision == :no_stream
            raise WrongExpectedRevisionError.new(
              revision:, expected_revision:, stream:
            )
          end
        end
      end
    end
  end
end

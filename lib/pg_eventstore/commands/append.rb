# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class Append < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @param events [Array<PgEventstore::Event>]
      # @param event_modifier [#call]
      # @param options [Hash]
      # @option options [Integer] :expected_revision provide your own revision number
      # @option options [Symbol] :expected_revision provide one of next values: :any, :no_stream or :stream_exists
      # @return [Array<PgEventstore::Event>] persisted events
      # @raise [PgEventstore::WrongExpectedRevisionError]
      def call(stream, *events, event_modifier:, options: {})
        raise SystemStreamError, stream if stream.system?

        events = events.map(&event_modifier.method(:call))
        queries.transactions.transaction do
          partitions = prepare_partitions(stream, events)
          stream_index = queries.streams_global_index.find_or_create_by(stream)
          revision = stream_index['stream_revision']
          assert_expected_revision!(revision, options[:expected_revision], stream) if options[:expected_revision]
          events.each.with_index(1) do |event, index|
            event.stream_revision = revision + index
          end
          revision += events.size
          queries.events.insert(stream, events).tap do |created_events|
            update_stream_index(stream_index, revision)
            index_events(created_events, partitions, stream_index['id'])
          end
        end
      end

      private

      # @param stream [PgEventstore::Stream]
      # @param events [Array<PgEventstore::Event>]
      # @return [Array<PgEventstore::Partition>]
      def prepare_partitions(stream, events)
        event_types = events.map { _1.type.to_s }.uniq
        existing_partitions = queries.partitions.partitions(
          [{ context: stream.context, stream_name: stream.stream_name }],
          event_types
        )
        missing_event_types = event_types - existing_partitions.map(&:event_type)
        raise MissingPartitions.new(stream, missing_event_types) if missing_event_types.any?

        existing_partitions
      end

      # @param events [Array<PgEventstore::Event>]
      # @param partitions [Array<PgEventstore::Partition>]
      # @param stream_index_id [Integer]
      # @return [void]
      def index_events(events, partitions, stream_index_id)
        partitions = partitions.to_h { [_1.event_type, _1.id] }
        indexes = events.map { [_1.global_position, partitions[_1.type], stream_index_id] }
        queries.events_global_index.create_global_indexes(indexes)
      end

      def update_stream_index(stream_index, stream_revision)
        queries.streams_global_index.update_revision(stream_index['id'], stream_revision:)
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

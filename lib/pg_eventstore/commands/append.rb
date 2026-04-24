# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class Append < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @param events [Array<PgEventstore::Event>]
      # @param options [Hash]
      # @option options [Integer] :expected_revision provide your own revision number
      # @option options [Symbol] :expected_revision provide one of next values: :any, :no_stream or :stream_exists
      # @param event_modifier [#call]
      # @return [Array<PgEventstore::Event>] persisted events
      # @raise [PgEventstore::WrongExpectedRevisionError]
      def call(stream, *events, options: {}, event_modifier: EventModifiers::PrepareRegularEvent.new)
        raise SystemStreamError, stream if stream.system?

        queries.transactions.transaction do
          revision = queries.events.stream_revision(stream) || Stream::NON_EXISTING_STREAM_REVISION
          assert_expected_revision!(revision, options[:expected_revision], stream) if options[:expected_revision]
          formatted_events = events.map.with_index(1) do |event, index|
            event_modifier.call(event, revision + index)
          end
          partitions = find_partitions(stream, formatted_events)
          queries.events.insert(stream, formatted_events).tap do |created_events|
            index_events(created_events, partitions)
          end
        end
      end

      private

      # @param stream [PgEventstore::Stream]
      # @param events [Array<PgEventstore::Event>]
      # @return [Array<PgEventstore::Partition>]
      def find_partitions(stream, events)
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
      # @return [void]
      def index_events(events, partitions)
        partitions = partitions.to_h { [_1.event_type, _1.id] }
        indexes = events.map { [_1.global_position, partitions[_1.type], _1.stream.stream_id] }
        queries.events_global_index.create_global_indexes(indexes)
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

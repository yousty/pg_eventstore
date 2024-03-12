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
      def call(stream, *events, options: {}, event_modifier: EventModifiers::PrepareRegularEvent)
        raise SystemStreamError, stream if stream.system?

        queries.transactions.transaction do
          revision = queries.events.stream_revision(stream) || Stream::NON_EXISTING_STREAM_REVISION
          assert_expected_revision!(revision, options[:expected_revision], stream) if options[:expected_revision]
          formatted_events = events.map.with_index(1) do |event, index|
            event_modifier.call(event, revision + index)
          end
          create_partitions(stream, formatted_events)
          queries.events.insert(stream, formatted_events)
        end
      end

      private

      # @param stream [PgEventstore::Stream]
      # @param events [Array<PgEventstore::Event>]
      # @return [void]
      def create_partitions(stream, events)
        # threads = events.map(&:type).uniq.map do |event_type|
        #   queries.partitions.create_partitions_async(stream, event_type)
        # end
        # raise TransactionQueries::RestartRequired if threads.any?
        missing_event_types = events.map(&:type).map(&:to_s).uniq.select do |event_type|
          queries.partitions.partition_required?(stream, event_type)
        end
        raise MissingPartitions.new(stream, missing_event_types) if missing_event_types.any?
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
              revision: revision, expected_revision: expected_revision, stream: stream
            )
          end

        in [Integer, Symbol]
          if revision == Stream::NON_EXISTING_STREAM_REVISION && expected_revision == :stream_exists
            raise WrongExpectedRevisionError.new(
              revision: revision, expected_revision: expected_revision, stream: stream
            )
          end
          if revision > Stream::NON_EXISTING_STREAM_REVISION && expected_revision == :no_stream
            raise WrongExpectedRevisionError.new(
              revision: revision, expected_revision: expected_revision, stream: stream
            )
          end
        end
      end
    end
  end
end

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
          stream = queries.streams.find_or_create_stream(stream)
          revision = stream.stream_revision
          assert_expected_revision!(revision, options[:expected_revision]) if options[:expected_revision]
          events.map.with_index(1) do |event, index|
            queries.events.insert(stream, event_modifier.call(event, revision + index))
          end.tap do
            queries.streams.update_stream_revision(stream, revision + events.size)
          end
        end
      end

      private

      # @param revision [Integer]
      # @param expected_revision [Symbol, Integer]
      # @raise [PgEventstore::WrongExpectedRevisionError] in case if revision does not satisfy expected revision
      # @return [void]
      def assert_expected_revision!(revision, expected_revision)
        return if expected_revision == :any

        case [revision, expected_revision]
        in [Integer, Integer]
          raise WrongExpectedRevisionError.new(revision, expected_revision) unless revision == expected_revision
        in [Integer, Symbol]
          if revision == Stream::INITIAL_STREAM_REVISION && expected_revision == :stream_exists
            raise WrongExpectedRevisionError.new(revision, expected_revision)
          end
          if revision > Stream::INITIAL_STREAM_REVISION && expected_revision == :no_stream
            raise WrongExpectedRevisionError.new(revision, expected_revision)
          end
        end
      end
    end
  end
end

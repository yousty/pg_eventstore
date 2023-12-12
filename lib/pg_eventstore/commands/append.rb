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
      # @return [Array<PgEventstore::Event>] persisted events
      # @raise [PgEventstore::WrongExpectedRevisionError]
      def call(stream, *events, options: {})
        raise SystemStreamError, stream if stream.system?

        queries.transaction do
          stream = queries.find_or_create_stream(stream)
          revision = stream.stream_revision
          assert_expected_revision!(revision, options[:expected_revision]) if options[:expected_revision]
          events.map.with_index(1) do |event, index|
            queries.insert(stream, prepared_event(event, revision + index))
          end.tap do
            queries.update_stream_revision(stream, revision + events.size)
          end
        end
      end

      private

      # @param event [PgEventstore::Event]
      # @param revision [Integer]
      # @return [PgEventstore::Event]
      def prepared_event(event, revision)
        event.class.new(
          id: event.id, data: event.data, metadata: event.metadata, type: event.type, stream_revision: revision
        )
      end

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

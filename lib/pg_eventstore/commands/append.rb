# frozen_string_literal: true

module PgEventstore
  module Commands
    class Append < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @param events [Array<PgEventstore::Event>]
      # @param options [Hash]
      # @option options [Integer] :expected_revision provide your own revision number
      # @option options [Symbol] :expected_revision provide one of next values: :any, :no_stream or :stream_exists
      # @return [Array<PgEventstore::Event>] persisted events
      # @raise [PgEventstore::WrongExpectedRevisionError]
      def call(stream, *events, options: {})
        queries.transaction do
          revision = queries.last_stream_event(stream)&.stream_revision || -1
          assert_expected_revision!(revision, options[:expected_revision]) if options[:expected_revision]
          events.map.with_index do |event, index|
            queries.insert(prepared_event(stream, event, revision + index + 1))
          end
        end
      end

      private

      # @param stream [PgEventstore::Stream]
      # @param event [PgEventstore::Event]
      # @param revision [Integer]
      # @return [PgEventstore::Event]
      def prepared_event(stream, event, revision)
        event.class.new(
          id: event.id, data: event.data, metadata: event.metadata, type: event.type, stream_revision: revision,
          **stream
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
          if revision == -1 && expected_revision == :stream_exists
            raise WrongExpectedRevisionError.new(revision, expected_revision)
          end
          if revision > -1 && expected_revision == :no_stream
            raise WrongExpectedRevisionError.new(revision, expected_revision)
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class LinkTo < AbstractCommand
      # @param stream [PgEventstore::Stream]
      # @param events [Array<PgEventstore::Event>]
      # @param options [Hash]
      # @option options [Integer] :expected_revision provide your own revision number
      # @option options [Symbol] :expected_revision provide one of next values: :any, :no_stream or :stream_exists
      # @return [Array<PgEventstore::Event>] persisted events
      # @raise [PgEventstore::WrongExpectedRevisionError]
      # @raise [PgEventstore::NotPersistedEventError]
      def call(stream, *events, options: {})
        check_events_presence(events)
        append_cmd = Append.new(queries)
        append_cmd.call(
          stream, *events, options:, event_modifier: EventModifiers::PrepareLinkEvent.new(queries.partitions)
        )
      end

      private

      # Checks if the given events are persisted events. This is needed to prevent potentially non-existing id valuess
      # from appearing in #link_id column.
      # @param events [Array<PgEventstore::Event>]
      # @return [void]
      def check_events_presence(events)
        ids_from_db = queries.events.ids_from_db(events)
        missing_ids = events.map(&:id) - ids_from_db
        return if missing_ids.empty?

        missing_event = events.find { |event| event.id == missing_ids.first }
        raise NotPersistedEventError, missing_event
      end
    end
  end
end

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
        events.each(&method(:check_id_presence))
        append_cmd = Append.new(queries)
        append_cmd.call(stream, *events, options: options, event_modifier: EventModifiers::PrepareLinkEvent)
      end

      private

      # Checks if Event#id is present. An event must have the #id value in order to be linked.
      # @param event [PgEventstore::Event]
      # @return [void]
      def check_id_presence(event)
        return unless event.id.nil?

        raise NotPersistedEventError, event
      end
    end
  end
end

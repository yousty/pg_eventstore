# frozen_string_literal: true

module PgEventstore
  module Commands
    # @!visibility private
    class DeleteEvent < AbstractCommand
      # Determines max allowed number of records to lock during an update. If the threshold is reached - an error is
      # raised.
      # @return [Integer]
      MAX_RECORDS_TO_LOCK = 1_000

      # @param event [PgEventstore::Event]
      # @param force [Boolean]
      # @return [Boolean]
      def call(event, force:)
        check_records_number_to_lock(event) unless force
        queries.maintenance.delete_event(event)
        true
      end

      private

      # @param event [PgEventstore::Event]
      # @return [void]
      # @raise [PgEventstore::TooManyRecordsToLockError]
      def check_records_number_to_lock(event)
        records_to_lock = queries.maintenance.events_to_lock_count(event.stream, event.stream_revision)
        raise TooManyRecordsToLockError.new(event.stream, records_to_lock) if records_to_lock > MAX_RECORDS_TO_LOCK
      end
    end
  end
end

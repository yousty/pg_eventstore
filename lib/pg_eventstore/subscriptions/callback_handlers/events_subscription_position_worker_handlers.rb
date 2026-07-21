# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventsSubscriptionPositionWorkerHandlers
    include Extensions::CallbackHandlersExtension

    class << self
      # @param event_subscription_position_queries [PgEventstore::EventSubscriptionPositionQueries]
      # @param update_interval [Integer, Float]
      # @return [void]
      def assign_subscription_position(event_subscription_position_queries, update_interval)
        affected_records = event_subscription_position_queries.assign_subscription_position
        # In case if assigning subscription position process is locked by someone else or if we updated less than
        # MAX_INDEX_RECORDS_TO_UPDATE_SUBSCRIPTION_POSITION number of records(which basically means we are on the edge
        # of the table) - take some delay before the next attempt.
        if affected_records.nil? ||
           affected_records < EventSubscriptionPositionQueries::MAX_INDEX_RECORDS_TO_UPDATE_SUBSCRIPTION_POSITION
          sleep update_interval
        end
      end

      # @param event_subscription_position_queries [PgEventstore::EventSubscriptionPositionQueries]
      # @param next_reindex_at [PgEventstore::EventsSubscriptionPositionWorker::ReindexTime]
      # @return [void]
      def reindex(event_subscription_position_queries, next_reindex_at)
        return if next_reindex_at.time && next_reindex_at.time > Time.now

        time = event_subscription_position_queries.reindex_unprocessed_positions
        return unless time

        next_reindex_at.time = time
      end
    end
  end
end

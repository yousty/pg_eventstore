# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventsSubscriptionPositionWorkerHandlers
    include Extensions::CallbackHandlersExtension

    class << self
      # @param subscription_service_queries [PgEventstore::SubscriptionServiceQueries]
      # @param update_interval [Integer, Float]
      # @return [void]
      def assign_subscription_position(subscription_service_queries, update_interval)
        affected_records = subscription_service_queries.assign_subscription_position
        # In case if assigning subscription position process is locked by someone else or if we updated less than
        # MAX_INDEX_RECORDS_TO_UPDATE_SUBSCRIPTION_POSITION number of records(which basically means we are on the edge
        # of the table) - take some delay before the next attempt.
        if affected_records.nil? ||
           affected_records < SubscriptionServiceQueries::MAX_INDEX_RECORDS_TO_UPDATE_SUBSCRIPTION_POSITION
          sleep update_interval
        end
      end
    end
  end
end

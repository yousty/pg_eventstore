# frozen_string_literal: true

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('CLUSTER events_global_index USING idx_events_idx_on_global_position')
end

subscription_service_queries = PgEventstore::SubscriptionServiceQueries.new(
  PgEventstore.connection(:_eventstore_db_connection)
)

loop do
  break if subscription_service_queries.assign_subscription_position == 0
end

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('VACUUM (ANALYZE) events_global_index;')
end

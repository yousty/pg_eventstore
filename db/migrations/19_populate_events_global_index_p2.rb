# frozen_string_literal: true

puts 'Running cluster on events_global_index. This may take some time.'
PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('CLUSTER events_global_index USING idx_events_idx_on_global_position')
end

subscription_service_queries = PgEventstore::SubscriptionServiceQueries.new(
  PgEventstore.connection(:_eventstore_db_connection)
)

total_count = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('select count(*) as c_all from events_global_index where subscription_position is null')
end.first['c_all'] || 0
processed = 0
puts "Assigning event subscription positions. Total count: #{total_count} events."

loop do
  updated_num = subscription_service_queries.assign_subscription_position
  break if updated_num == 0

  processed += updated_num
  print "Processed: #{processed}. Left: #{total_count - processed}                    \r"
end

puts
puts 'Running vacuum on events_global_index. This may take some time.'
PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('VACUUM (ANALYZE) events_global_index')
end

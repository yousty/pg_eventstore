# frozen_string_literal: true

event_subscription_position_queries = PgEventstore::EventSubscriptionPositionQueries.new(
  PgEventstore.connection(:_eventstore_db_connection)
)

total_count = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('select count(*) as c_all from event_subscription_positions_unprocessed')
end.first['c_all'] || 0
processed = 0
puts "Assigning event subscription positions. Total count: #{total_count} events."

loop do
  updated_num = event_subscription_position_queries.assign_subscription_position
  break if updated_num == 0

  processed += updated_num
  print "Processed: #{processed}. Left: #{total_count - processed}                    \r"
end

puts
PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  puts 'Running vacuum on event_subscription_positions_unprocessed. This may take some time.'
  conn.exec('VACUUM (ANALYZE) event_subscription_positions_unprocessed')
end

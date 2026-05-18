# frozen_string_literal: true

CONCURRENCY = ENV['CONCURRENCY18']&.to_i || ENV['CONCURRENCY']&.to_i || 100

PgEventstore.configure(name: :_eventstore_db_connection) do |config|
  config.connection_pool_size = CONCURRENCY
end

partitions = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('select * from partitions')
end.to_a
context_partitions = partitions.select { _1['stream_name'].nil? }.to_h { [_1['context'], _1['id']] }
event_type_partitions = partitions.reject { _1['stream_name'].nil? }.group_by { _1['context'] }
event_type_partitions = event_type_partitions.map do |context, context_parts|
  context_parts = context_parts.group_by { |p| p['stream_name'] }
  context_parts = context_parts.map do |stream_name, parts|
    stream_name_part = parts.find { _1['event_type'].nil? }
    event_type_parts = parts - [stream_name_part]
    event_type_parts = event_type_parts.map do |part|
      [part['event_type'], part]
    end
    [stream_name, { stream_name_part:, event_types: event_type_parts.to_h }]
  end
  [context, context_parts.to_h]
end.to_h

total_events = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('explain select * from events')
end.first['QUERY PLAN'][/rows=\d+/].sub('rows=', '').to_i

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('delete from events_global_index')
end

puts "Indexing events. Events to process: #{total_events} (approximately). Concurrency is #{CONCURRENCY} concurrent readers."
puts

find_stream_part = ->(event) {
  partition = event_type_partitions.dig(event['context'], event['stream_name'], :stream_name_part)
  partition || raise("Could not resolve stream name partition of #{event.inspect}")
}

find_event_part = ->(event) {
  partition = event_type_partitions.dig(event['context'], event['stream_name'], :event_types, event['type'])
  partition || raise("Could not resolve event type partition of #{event.inspect}")
}
processed = 0
processed_was = 0
time = Time.now
global_position = 0
# Unfortunately we can't write concurrently here because we want records to appear in the order they appear in events
# table.
loop do
  events = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
    conn.exec_params(<<~SQL, [global_position])
      select global_position, context, stream_name, type, stream_id, stream_revision
      from events
      where global_position > $1
      order by global_position asc
      limit 10_000
    SQL
  end.to_a
  break if events.empty?

  global_position = events.last['global_position']
  processed += events.size
  stream_ids = {}
  events.each_slice(CONCURRENCY) do |sliced_events|
    query_runner = PgEventstore::AsyncQueryRunner.new
    sliced_events.each do |event|
      query_runner.async do
        query_strategy = PgEventstore::QueryStrategy::Async.new(PgEventstore.connection(:_eventstore_db_connection))
        sql_builder = PgEventstore::SQLBuilder.new.from('streams_global_index')
        sql_builder.select('id')
        sql_builder.where(
          'stream_id = ? and partition_id = ?',
          event['stream_id'], find_stream_part.(event)['id']
        )
        attrs = query_strategy.exec_params(*sql_builder.to_exec_params).to_a.first
        stream_ids[event['global_position']] = attrs['id']
      end
    end
    query_runner.run
  end

  values = events.map do |event|
    stream_idx_id = stream_ids[event['global_position']]
    ctx_partition_id = context_partitions[event['context']]
    stream_name_partition_id = find_stream_part.(event)['id']
    event_type_partition_id = find_event_part.(event)['id']
    "(#{event['global_position']}, #{ctx_partition_id}, #{stream_name_partition_id}, #{event_type_partition_id}, #{stream_idx_id}, #{event['stream_revision']})"
  end.join(',')

  PgEventstore.connection(:_eventstore_db_connection).with do |conn|
    conn.exec(<<~SQL)
      INSERT INTO events_global_index ("global_position", "context_partition_id", "stream_name_partition_id", "event_type_partition_id", "streams_global_index_id", "stream_revision")
      VALUES #{values}
    SQL
  end

  time_was = time
  time = Time.now

  performance_info = <<~TEXT.strip
      Processed: #{processed}. Left: #{total_events - processed}(approximately). \
      Performance: #{((processed - processed_was) / (time - time_was)).round(2)} events/second.
    TEXT
  processed_was = processed
  print "#{performance_info}               \r"
end

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('VACUUM (ANALYZE) events_global_index;')
end

# frozen_string_literal: true

CONCURRENCY = ENV['CONCURRENCY']&.to_i || 10

PgEventstore.configure(name: :_eventstore_db_connection) do |config|
  config.connection_pool_size = CONCURRENCY
end

partitions = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('select * from partitions where event_type is not null')
end
partitions = partitions.to_a.group_by { _1['context'] }
partitions = partitions.map do |context, context_parts|
  context_parts = context_parts.group_by { |p| p['stream_name'] }
  context_parts = context_parts.map do |stream_name, parts|
    parts = parts.map do |part|
      [part['event_type'], part['id']]
    end
    [stream_name, parts.to_h]
  end
  [context, context_parts.to_h]
end.to_h

total_events = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('select count(*) all_count from events')
end.first['all_count']

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('delete from events_global_index')
end

puts "Indexing events. Events to process: #{total_events}. Concurrency is #{CONCURRENCY} concurrent writers."
processed = 0
processed_was = 0
time = Time.now
lock = Thread::Mutex.new
threads = CONCURRENCY.times.map do |t|
  Thread.new do
    global_position = 0
    loop do
      events = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
        conn.exec_params(<<~SQL, [global_position, CONCURRENCY, t])
          select global_position, context, stream_name, type, stream_id
          from events
          where global_position > $1 and global_position % $2 = $3
          order by global_position asc
          limit 1_000
        SQL
      end.to_a
      break if events.empty?

      global_position = events.last['global_position']
      lock.synchronize { processed += events.size }

      values = events.map do |event|
        "(#{event['global_position']}, #{partitions[event['context']][event['stream_name']][event['type']]}, '#{PG::Connection.escape(event['stream_id'])}')"
      end.join(',')

      PgEventstore.connection(:_eventstore_db_connection).with do |conn|
        conn.exec(<<~SQL)
          INSERT INTO events_global_index ("global_position", "partition_id", "stream_id") VALUES #{values}
        SQL
      end

      # Only log from the first thread to prevent messages spam
      next unless t == 0

      lock.synchronize do
        time_was = time
        time = Time.now

        performance_info = <<~TEXT.strip
          Processed: #{processed}. Left: #{total_events - processed}. \
          Performance: #{((processed - processed_was) / (time - time_was)).round(2)} events/second.
        TEXT
        processed_was = processed
        print "#{performance_info}               \r"
      end
    end
  end
end
threads.each(&:join)

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('VACUUM (ANALYZE) events_global_index;')
end

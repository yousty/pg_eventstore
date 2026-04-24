# frozen_string_literal: true

CONCURRENCY = ENV['CONCURRENCY']&.to_i || 10

PgEventstore.configure(name: :_eventstore_db_connection) do |config|
  config.connection_pool_size = CONCURRENCY
end

partitions = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('select * from partitions where context is not null and stream_name is not null and event_type is null')
end
partitions = partitions.to_a.group_by { _1['context'] }
partitions = partitions.to_h do |context, context_parts|
  context_parts = context_parts.to_h { |p| [p['stream_name'], p['id']] }
  [context, context_parts]
end

total_streams = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('select count(*) all_count from "$streams"')
end.first['all_count']

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('delete from streams_global_index')
end

puts "Indexing streams. Streams to process: #{total_streams}. Concurrency is #{CONCURRENCY} concurrent writers."
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
          select global_position, context, stream_name, stream_id
          from "$streams"
          where global_position > $1 and global_position % $2 = $3
          order by global_position asc
          limit 100
        SQL
      end.to_a
      break if events.empty?

      global_position = events.last['global_position']

      events = events.to_h { [_1['global_position'], _1] }

      # retrieve stream revision
      q = []
      events.each do |global_position, event|
        context = PG::Connection.escape(event['context'])
        stream_name = PG::Connection.escape(event['stream_name'])
        stream_id = PG::Connection.escape(event['stream_id'])
        q << <<~SQL
          (
            select max(stream_revision) as stream_revision, #{global_position} as group_id
            from events
            where context = '#{context}' and stream_name = '#{stream_name}' and stream_id = '#{stream_id}'
          )
        SQL
      end
      stream_revisions = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
        conn.exec(q.join(' union all ')).to_a
      end.to_a
      stream_revisions.each do |attrs|
        events[attrs['group_id']]['stream_revision'] = attrs['stream_revision']
      end

      values = events.each_value.map do |event|
        partition_id = partitions[event['context']][event['stream_name']]
        stream_id = PG::Connection.escape(event['stream_id'])
        stream_revision = event['stream_revision']
        "(#{partition_id}, '#{stream_id}', #{stream_revision})"
      end.join(',')

      PgEventstore.connection(:_eventstore_db_connection).with do |conn|
        conn.exec(<<~SQL)
          INSERT INTO streams_global_index ("partition_id", "stream_id", "stream_revision") VALUES #{values}
        SQL
      end

      lock.synchronize { processed += events.size }

      # Only log from the first thread to prevent messages spam
      next unless t == 0

      lock.synchronize do
        time_was = time
        time = Time.now

        performance_info = <<~TEXT.strip
          Processed: #{processed}. Left: #{total_streams - processed}. \
          Performance: #{((processed - processed_was) / (time - time_was)).round(2)} streams/second.
        TEXT
        processed_was = processed
        print "#{performance_info}               \r"
      end
    end
  end
end
threads.each(&:join)

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('VACUUM (ANALYZE) streams_global_index;')
end

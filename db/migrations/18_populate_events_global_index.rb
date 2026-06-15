# frozen_string_literal: true

CONCURRENCY = ENV['CONCURRENCY']&.to_i || 10

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

puts "Indexing events. Events to process: #{total_events} (approximately). Concurrency is #{CONCURRENCY} concurrent writers."
puts
processed = 0
processed_was = 0
time = Time.now
lock = Thread::Mutex.new
threads = CONCURRENCY.times.map do |t|
  Thread.new do
    event_type_partitions.each_value do |stream_name_parts|
      stream_name_parts.each_value do |partitions_info|
        event_type_parts = partitions_info[:event_types]
        stream_name_part = partitions_info[:stream_name_part]
        event_type_parts.each_value do |event_type_part|
          global_position = 0
          loop do
            events = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
              conn.exec_params(<<~SQL, [global_position, CONCURRENCY, t])
                select global_position, context, stream_name, type, stream_id, stream_revision
                from #{event_type_part['table_name']}
                where global_position > $1 and global_position % $2 = $3
                order by global_position asc
                limit 1_000
              SQL
            end.to_a
            break if events.empty?

            global_position = events.last['global_position']
            stream_builders = events.map do |event|
              sql_builder = PgEventstore::SQLBuilder.new.from('streams_global_index')
              sql_builder.select(%( id, #{event['global_position']} as event_global_position ))
              sql_builder.where(
                'stream_id = ? and partition_id = ?',
                event['stream_id'], stream_name_part['id']
              )
            end
            final_streams_builder = PgEventstore::SQLBuilder.union_builders(stream_builders)
            stream_ids = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
              conn.exec_params(*final_streams_builder.to_exec_params)
            end.to_a
            stream_ids = stream_ids.to_h { [_1['event_global_position'], _1['id']] }

            values = events.map do |event|
              stream_idx_id = stream_ids[event['global_position']]
              ctx_partition_id = context_partitions[event['context']]
              stream_name_partition_id = stream_name_part['id']
              event_type_partition_id = event_type_part['id']
              "(#{event['global_position']}, #{ctx_partition_id}, #{stream_name_partition_id}, #{event_type_partition_id}, #{stream_idx_id}, #{event['stream_revision']})"
            end.join(',')

            PgEventstore.connection(:_eventstore_db_connection).with do |conn|
              conn.exec(<<~SQL)
                INSERT INTO events_global_index ("global_position", "context_partition_id", "stream_name_partition_id", "event_type_partition_id", "streams_global_index_id", "stream_revision") VALUES #{values}
              SQL
            end

            lock.synchronize do
              processed += events.size
              time_was = time
              time = Time.now

              performance_info = <<~TEXT.strip
                Processed: #{processed}. Left: #{total_events - processed}(approximately). \
                Performance: #{((processed - processed_was) / (time - time_was)).round(2)} events/second.
              TEXT
              processed_was = processed
              print "#{performance_info}               \r"
            end
          end
        end
      end
    end
  end
end
threads.each(&:join)

puts

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  puts 'Running cluster on events_global_index. This may take some time.'
  conn.exec('CLUSTER events_global_index USING idx_events_idx_on_global_position')
  puts 'Running vacuum on events_global_index. This may take some time.'
  conn.exec('VACUUM (ANALYZE) events_global_index')
end

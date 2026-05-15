# frozen_string_literal: true

CONCURRENCY = ENV['CONCURRENCY']&.to_i || 10

PgEventstore.configure(name: :_eventstore_db_connection) do |config|
  config.connection_pool_size = CONCURRENCY * 10
end

partitions = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('select * from partitions where event_type is null')
end.to_a

stream_name_partitions = partitions.reject { _1['stream_name'].nil? }.group_by { _1['context'] }
stream_name_partitions = stream_name_partitions.to_h do |context, context_parts|
  context_parts = context_parts.to_h { |p| [p['stream_name'], p['id']] }
  [context, context_parts]
end

total_streams = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('explain select * from "$streams"')
end.first['QUERY PLAN'][/rows=\d+/].sub('rows=', '').to_i

tables = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('select table_name from partitions where event_type is not null')
end.to_a.map { _1['table_name'] }

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('delete from streams_global_index')
end

puts "Indexing streams. Approximate number of streams to process: #{total_streams}. Concurrency is #{CONCURRENCY} concurrent writers."
puts <<~TEXT
  This migration consumes CONCURRENCY x10 connections. Make sure you have plenty of them. Migrations are idempotent, \
  so you can break, adjust settings if needed and then start over.
TEXT
puts

processed = 0
processed_was = 0
time = Time.now
lock = Thread::Mutex.new
threads = CONCURRENCY.times.map do |t|
  Thread.new do
    tables.each do |table|
      global_position = 0
      loop do
        events = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
          conn.exec_params(<<~SQL, [global_position, CONCURRENCY, t])
            select context, stream_name, stream_id, global_position
            from "#{table}"
            where global_position > $1 and global_position % $2 = $3 and stream_revision = 0
            group by context, stream_name, stream_id, global_position
            order by global_position asc
            limit 100
          SQL
        end.to_a
        break if events.empty?

        global_position = events.last['global_position']

        # retrieve stream revision
        events.each_slice(10) do |sliced_events|
          query_runner = PgEventstore::AsyncQueryRunner.new
          sliced_events.each do |event|
            query_runner.async do
              query_strategy = PgEventstore::QueryStrategy::Async.new(PgEventstore.connection(:_eventstore_db_connection))
              context = PG::Connection.escape(event['context'])
              stream_name = PG::Connection.escape(event['stream_name'])
              stream_id = PG::Connection.escape(event['stream_id'])
              q = <<~SQL
                select max(stream_revision) as stream_revision
                from events
                where context = '#{context}' and stream_name = '#{stream_name}' and stream_id = '#{stream_id}'
              SQL
              attrs = query_strategy.exec(q).to_a.first
              event['stream_revision'] = attrs['stream_revision']
            end
          end
          query_runner.run
        end

        values = events.map do |event|
          partition_id = stream_name_partitions[event['context']][event['stream_name']]
          stream_id = PG::Connection.escape(event['stream_id'])
          stream_revision = event['stream_revision']
          starting_position = event['global_position']
          "(#{partition_id}, '#{stream_id}', #{stream_revision}, #{starting_position})"
        end.join(',')

        PgEventstore.connection(:_eventstore_db_connection).with do |conn|
          conn.exec(<<~SQL)
            INSERT INTO streams_global_index
              ("partition_id", "stream_id", "stream_revision", "starting_position")
            VALUES #{values}
          SQL
        end

        lock.synchronize { processed += events.size }

        # Only log from the first thread to prevent messages spam
        next unless t == 0

        lock.synchronize do
          time_was = time
          time = Time.now

          performance_info = <<~TEXT.strip
            Processed: #{processed}. Left: #{total_streams - processed} (approximately). \
            Performance: #{((processed - processed_was) / (time - time_was)).round(2)} streams/second.
          TEXT
          processed_was = processed
          print "#{performance_info}               \r"
        end
      end
    end
  end
end
threads.each(&:join)

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('VACUUM (ANALYZE) streams_global_index;')
end

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
sub_partitions_count_cache = {}
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
          query_runner = PgEventstore::AsyncRunner.new
          sliced_events.each do |event|
            query_runner.async do
              query_strategy = PgEventstore::QueryStrategy::Async.new(PgEventstore.connection(:_eventstore_db_connection))
              context = event['context']
              stream_name = event['stream_name']
              stream_id = event['stream_id']
              sub_partitions_count_cache[[context, stream_name]] ||= query_strategy.exec_params(
                'select count(*) as c_all from partitions where context = $1 and stream_name = $2',
                [context, stream_name]
              ).first['c_all']
              if sub_partitions_count_cache[[context, stream_name]] > 50
                sub_partitions = query_strategy.exec_params(<<~SQL, [context, stream_name]).map { _1['table_name'] }
                  select table_name from partitions where context = $1 and stream_name = $2 and event_type is not null
                SQL
                max_revisions = []
                sub_partitions.each_slice(50) do |table_names|
                  q_parts = table_names.map do |table_name|
                    <<~SQL
                      select max(stream_revision) as stream_revision
                      from #{table_name}
                      where context = $1 and stream_name = $2 and stream_id = $3
                    SQL
                  end
                  q_parts = q_parts.map { "(#{_1})" }.join(' union all ')
                  q = "select coalesce(max(stream_revision), -1) as stream_revision from (#{q_parts})"
                  max_revisions.push(
                    query_strategy.exec_params(q, [context, stream_name, stream_id]).first['stream_revision']
                  )
                end
                event['stream_revision'] = max_revisions.max
              else
                q = <<~SQL
                  select max(stream_revision) as stream_revision
                  from events
                  where context = $1 and stream_name = $2 and stream_id = $3
                SQL
                attrs = query_strategy.exec_params(q, [context, stream_name, stream_id]).to_a.first
                event['stream_revision'] = attrs['stream_revision']
              end
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

        lock.synchronize do
          processed += events.size
          next if Time.now - time < 2

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
  puts 'Running cluster on streams_global_index. This may take some time.'
  conn.exec('CLUSTER streams_global_index USING idx_streams_global_index_on_starting_position')
  puts 'Running vacuum on streams_global_index. This may take some time.'
  conn.exec('VACUUM (ANALYZE) streams_global_index')
end

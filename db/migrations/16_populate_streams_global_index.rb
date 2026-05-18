# frozen_string_literal: true

CONCURRENCY = ENV['CONCURRENCY16']&.to_i || ENV['CONCURRENCY']&.to_i || 100

PgEventstore.configure(name: :_eventstore_db_connection) do |config|
  config.connection_pool_size = CONCURRENCY
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

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('delete from streams_global_index')
end

puts "Indexing streams. Approximate number of streams to process: #{total_streams}. Concurrency is #{CONCURRENCY} concurrent readers."
puts

processed = 0
processed_was = 0
time = Time.now
global_position = 0
# Unfortunately we can't write concurrently here because we want records to appear in the order they appear in events
# table. This way we persist the correlation between streams_global_index.starting_position and streams_global_index
# records order on disk as it would appear in the fresh database.
loop do
  events = PgEventstore.connection(:_eventstore_db_connection).with do |conn|
    conn.exec_params(<<~SQL, [global_position])
      select context, stream_name, stream_id, global_position
      from events
      where global_position > $1 and stream_revision = 0
      group by context, stream_name, stream_id, global_position
      order by global_position asc
      limit 10_000
    SQL
  end.to_a
  break if events.empty?

  global_position = events.last['global_position']

  # retrieve stream revision
  events.each_slice(CONCURRENCY) do |sliced_events|
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

  processed += events.size

  time_was = time
  time = Time.now

  performance_info = <<~TEXT.strip
      Processed: #{processed}. Left: #{total_streams - processed} (approximately). \
      Performance: #{((processed - processed_was) / (time - time_was)).round(2)} streams/second.
    TEXT
  processed_was = processed
  print "#{performance_info}               \r"
end

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('VACUUM (ANALYZE) streams_global_index;')
end

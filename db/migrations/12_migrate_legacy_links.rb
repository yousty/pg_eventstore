# frozen_string_literal: true

CONCURRENCY = ENV['CONCURRENCY']&.to_i || 10

PgEventstore.configure do |config|
  config.connection_pool_size = CONCURRENCY
end

partitions = PgEventstore.connection.with do |conn|
  conn.exec('select id, table_name from partitions')
end
partitions = partitions.to_h { |attrs| [attrs['id'], attrs['table_name']] }

total_links = PgEventstore.connection.with do |conn|
  conn.exec_params(
    'select count(*) all_count from events where events.type = $1 and link_global_position is null',
    [PgEventstore::Event::LINK_TYPE]
  )
end.first['all_count']

puts "Migrating legacy links. Links to process: #{total_links}. Concurrency is #{CONCURRENCY} concurrent writers."
processed = 0
processed_was = 0
time = Time.now
lock = Thread::Mutex.new
threads = CONCURRENCY.times.map do |t|
  Thread.new do
    loop do
      link_events = PgEventstore.connection.with do |conn|
        conn.exec_params(<<~SQL, [PgEventstore::Event::LINK_TYPE, CONCURRENCY, t])
          select * from events
            where events.type = $1 and events.link_global_position is null and global_position % $2 = $3
            limit 1_000
        SQL
      end.to_a
      break if link_events.empty?

      lock.synchronize { processed += link_events.size }
      link_events = link_events.to_h { [_1['global_position'], _1] }
      builders = link_events.values.map do |event|
        builder = PgEventstore::SQLBuilder.new
        builder.select("global_position, #{event['global_position']} as link_event_global_position")
        builder.from(partitions[event['link_partition_id']]).where('id = ?', event['link_id'])
      end
      final_builder = PgEventstore::SQLBuilder.union_builders(builders)

      positions_map = PgEventstore.connection.with do |conn|
        conn.exec_params(*final_builder.to_exec_params)
      end.to_a

      update_queries = positions_map.map do |attrs|
        <<~SQL
          UPDATE events SET link_global_position = #{attrs['global_position']}
            WHERE global_position = #{attrs['link_event_global_position']};
        SQL
      end

      PgEventstore.connection.with do |conn|
        conn.exec(update_queries.join("\n"))
      end

      # Only log from the first thread to prevent messages spam
      next unless t == 0

      lock.synchronize do
        time_was = time
        time = Time.now

        performance_info = <<~TEXT.strip
          Processed: #{processed}. Left: #{total_links - processed}. \
          Performance: #{((processed - processed_was) / (time - time_was)).round(2)} events/second.
        TEXT
        processed_was = processed
        print "#{performance_info}               \r"
      end
    end
  end
end
threads.each(&:join)

PgEventstore.connection.with do |conn|
  conn.exec('VACUUM (ANALYZE) events;')
end

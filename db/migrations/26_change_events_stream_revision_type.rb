# frozen_string_literal: true

puts <<~TEXT
  Changing stream_revision from int to bigint. In order to do so we need to detach each event type partition, change \
  stream_revision column type and attach the partition again to the partent table.
TEXT

filters = PgEventstore::QueryBuilders::Filters::Collection.new
partition_queries = PgEventstore::PartitionQueries.new(PgEventstore.connection(:_eventstore_db_connection))

event_type_partitions = partition_queries.partitions(filters)

PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  event_type_partitions.each do |partition|
    begin
      partition_queries.detach_event_type_partition(partition)
    rescue PG::UndefinedTable
      # the partition was already detached in previous runs. Just proceed to the next step
    end

    puts "Starting changing stream_revision from int to bigint for #{partition.event_type.inspect} event type partition."
    conn.exec("ALTER TABLE #{partition.table_name} ALTER COLUMN stream_revision TYPE bigint")
  end

  conn.exec('ALTER TABLE events ALTER COLUMN stream_revision TYPE bigint')

  event_type_partitions.each do |partition|
    partition_queries.attach_event_type_partition(partition)
  end
end

puts 'Running vacuum on events.'
PgEventstore.connection(:_eventstore_db_connection).with do |conn|
  conn.exec('VACUUM (ANALYZE) events')
end

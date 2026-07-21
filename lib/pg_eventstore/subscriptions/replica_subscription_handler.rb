# frozen_string_literal: true

module PgEventstore
  class ReplicaSubscriptionHandler
    def initialize(config_name, replica_config_name)
      @replica_config_name = replica_config_name
      @config_name = config_name
    end

    # @param indexes [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
    # @return [void]
    def call(indexes)
      indexes = reject_already_processed(indexes)
      runner = AsyncRunner.new
      objects_to_migrate = {}
      runner.async do
        objects_to_migrate[:raw_events] = source_replica_queries.load_events(indexes)
      end
      runner.async do
        objects_to_migrate[:markers_index] = source_replica_queries.load_event_markers_index(indexes)
        objects_to_migrate[:markers] = source_replica_queries.load_markers(objects_to_migrate[:markers_index])
      end
      runner.async do
        objects_to_migrate[:events_index] = source_replica_queries.load_events_global_index(indexes)
        objects_to_migrate[:streams_index] = source_replica_queries.load_streams_global_index(
          objects_to_migrate[:events_index]
        )
        objects_to_migrate[:partitions] = source_replica_queries.load_partitions(objects_to_migrate[:events_index])
      end
      runner.run

      sql = []
      sql << records_to_sql(
        QueryBuilders::PartitionsFiltering::TABLE_NAME,
        Partition.options.map(&:name),
        objects_to_migrate[:partitions].map(&:options_hash),
        on_conflict: 'on conflict do nothing'
      )
      sql << records_to_sql(
        Event::PRIMARY_TABLE_NAME,
        RawEvent.options.map(&:name),
        objects_to_migrate[:raw_events].map(&:options_hash)
      )
      sql << records_to_sql(
        QueryBuilders::EventsGlobalIndexFiltering::PRIMARY_TABLE_NAME,
        EventGlobalIndex.options.map(&:name),
        objects_to_migrate[:events_index].map(&:options_hash)
      )
      sql << records_to_sql(
        QueryBuilders::StreamsGlobalIndexFiltering::PRIMARY_TABLE_NAME,
        StreamGlobalIndex.options.map(&:name),
        objects_to_migrate[:streams_index].map(&:options_hash),
        on_conflict: 'on conflict (id) do update set stream_revision = EXCLUDED.stream_revision'
      )
      sql << records_to_sql(
        QueryBuilders::EventSubscriptionPositionsFiltering::PRIMARY_TABLE_NAME,
        %i[global_position subscription_position],
        indexes.map(&:to_subscription_position_attrs)
      )
      if objects_to_migrate[:markers_index].any?
        sql << records_to_sql(
          QueryBuilders::EventMarkersIndexFiltering::PRIMARY_TABLE_NAME,
          EventMarkerIndex.options.map(&:name),
          objects_to_migrate[:markers_index].map(&:options_hash)
        )
      end
      if objects_to_migrate[:markers].any?
        sql << records_to_sql(
          QueryBuilders::EventMarkersFiltering::PRIMARY_TABLE_NAME,
          EventMarker.options.map(&:name),
          objects_to_migrate[:markers].map(&:options_hash),
          on_conflict: 'on conflict do nothing'
        )
      end
      sql = sql.join("\n")
      replica_transaction_queries.transaction(:read_committed) do
        replica_connection.with do |conn|
          conn.exec(sql)
        end
      end
    end

    private

    # @param indexes [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
    # @return [Array<PgEventstore::EventGlobalIndex::SubscriptionRepr>]
    def reject_already_processed(indexes)
      existing_positions = destination_replica_queries.load_subscription_positions(indexes)
      return indexes if existing_positions.empty?

      indexes.reject do |index|
        existing_positions.include?(index.subscription_position)
      end
    end

    # @param table_name [String]
    # @param attribute_names [Array<Symbol>]
    # @param attributes_collection [Array<Hash<Symbol, Object>>]
    # @param on_conflict [String, nil]
    # @return [String]
    def records_to_sql(table_name, attribute_names, attributes_collection, on_conflict: nil)
      sql_values = attributes_collection.map do |attributes|
        values = attribute_names.map do |attribute_name|
          connection.with do |conn|
            conn.prepared_value(attributes[attribute_name])
          end
        end
        "(#{values.join(', ')})"
      end
      sql_values = sql_values.join(', ')
      attributes = attribute_names.join(', ')
      "insert into #{table_name} (#{attributes}) values #{sql_values} #{on_conflict if on_conflict};"
    end

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(@config_name)
    end

    # @return [PgEventstore::Connection]
    def replica_connection
      PgEventstore.connection(@replica_config_name)
    end

    # @return [PgEventstore::TransactionQueries]
    def replica_transaction_queries
      TransactionQueries.new(replica_connection)
    end

    # @return [PgEventstore::ReplicaQueries]
    def source_replica_queries
      ReplicaQueries.new(connection, QueryStrategy::Async.new(connection))
    end

    # @return [PgEventstore::ReplicaQueries]
    def destination_replica_queries
      ReplicaQueries.new(replica_connection, QueryStrategy::Foreground.new(replica_connection))
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class MaintenanceQueries
    EVENT_INDEXES_TO_REMOVE_PER_QUERY = 10_000
    EVENT_INDEXES_TO_UPDATE_PER_QUERY = 10_000

    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param stream [PgEventstore::Stream]
    # @return [Integer] number of deleted events of the given stream
    def delete_stream(stream)
      total_removed = 0
      transaction_queries.transaction(:read_commited) do
        stream_global_idx = streams_global_index_queries.find_by!(stream)
        streams_global_index_queries.delete(stream_global_idx.id)
        global_position = 1
        loop do
          deleted_events_global_index = connection.with do |conn|
            conn.exec_params(<<~SQL, [stream_global_idx.id, global_position, EVENT_INDEXES_TO_REMOVE_PER_QUERY]).to_a
              delete from events_global_index
                     where global_position in (
                         select global_position from events_global_index
                                  where streams_global_index_id = $1 and global_position >= $2
                                  order by global_position asc
                                  limit $3
                     )
                     returning event_type_partition_id, global_position
            SQL
          end
          break if deleted_events_global_index.empty?

          global_position = deleted_events_global_index.last['global_position'] + 1
          total_removed += deleted_events_global_index.size
          deleted_events_global_index = deleted_events_global_index.group_by { _1['event_type_partition_id'] }
          partitions = partition_queries.find_by_ids(deleted_events_global_index.keys).to_h { [_1['id'], _1] }
          queries = deleted_events_global_index.map do |partition_id, idxs|
            partition = partitions[partition_id]
            positions = idxs.map { _1['global_position'] }.join(', ')
            context = PG::Connection.escape(partition['context'])
            stream_name = PG::Connection.escape(partition['stream_name'])
            event_type = PG::Connection.escape(partition['event_type'])
            <<~SQL
              delete from events
                     where context = '#{context}' and stream_name = '#{stream_name}' and type = '#{event_type}'
                           and global_position in (#{positions});
            SQL
          end
          connection.with do |conn|
            conn.exec(queries.join("\n"))
          end
        end
      end
      total_removed
    end

    # @param event [PgEventstore::Event]
    # @return [void]
    def delete_event(event)
      stream = event.stream
      transaction_queries.transaction(:read_commited) do
        stream_global_idx = streams_global_index_queries.find_by!(stream)
        current_stream_revision = connection.with do |conn|
          conn.exec_params(
            'select stream_revision from streams_global_index where id = $1 for update', [stream_global_idx.id]
          )
        end.to_a.first['stream_revision']
        deleted_event = connection.with do |conn|
          conn.exec_params(<<~SQL, [stream_global_idx.id, event.global_position]).to_a.first
            delete from events_global_index where streams_global_index_id = $1 and global_position = $2
                   returning global_position, event_type_partition_id, stream_revision
          SQL
        end
        raise RecordNotFound.new('events_global_index', event.global_position) unless deleted_event

        return delete_stream(stream) if current_stream_revision == 0 && deleted_event['stream_revision'] == 0

        first_updated_event = nil
        stream_revision = deleted_event['stream_revision']
        loop do
          updated_events = connection.with do |conn|
            conn.exec_params(<<~SQL, [stream_global_idx.id, stream_revision, EVENT_INDEXES_TO_UPDATE_PER_QUERY]).to_a
              update events_global_index set stream_revision = stream_revision - 1
                     where global_position in (
                         select global_position from events_global_index
                                  where streams_global_index_id = $1 and stream_revision > $2
                                  order by stream_revision asc
                                  limit $3
                     )
                     returning event_type_partition_id, global_position, stream_revision
            SQL
          end
          first_updated_event ||= updated_events.first
          break if updated_events.empty?

          stream_revision += updated_events.size
          updated_events = updated_events.group_by { _1['event_type_partition_id'] }
          partitions = partition_queries.find_by_ids(updated_events.keys).to_h { [_1['id'], _1] }
          queries = updated_events.flat_map do |partition_id, idxs|
            partition = partitions[partition_id]
            context = PG::Connection.escape(partition['context'])
            stream_name = PG::Connection.escape(partition['stream_name'])
            event_type = PG::Connection.escape(partition['event_type'])
            idxs.map do |idx|
              <<~SQL
                update events set stream_revision = #{idx['stream_revision']}
                  where context = '#{context}' and stream_name = '#{stream_name}' and type = '#{event_type}' and
                        global_position = #{idx['global_position']};
              SQL
            end
          end
          connection.with do |conn|
            conn.exec(queries.join("\n"))
          end
        end
        # Adjust starting_position in case zero revision event was deleted
        if deleted_event['stream_revision'] == 0
          connection.with do |conn|
            conn.exec_params(
              'update streams_global_index set starting_position = $1 where id = $2',
              [first_updated_event['stream_revision'],
               stream_global_idx.id]
            )
          end
        end
      end
    end

    # @param stream [PgEventstore::Stream]
    # @param after_revision [Integer]
    # @return [Integer]
    def events_to_lock_count(stream, after_revision)
      stream_index = streams_global_index_queries.find_by(stream)
      stream_index.stream_revision - after_revision
    end

    private

    def streams_global_index_queries
      StreamsGlobalIndexQueries.new(connection, QueryStrategy::Foreground.new(connection))
    end

    def transaction_queries
      TransactionQueries.new(connection)
    end

    def partition_queries
      PartitionQueries.new(connection)
    end
  end
end

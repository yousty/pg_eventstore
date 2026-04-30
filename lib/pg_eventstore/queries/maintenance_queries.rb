# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class MaintenanceQueries
    EVENT_INDEXES_TO_REMOVE_PER_QUERY = 10_000

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
      streams_global_index_queries.delete(stream)
      connection.with do |conn|
        global_positions = conn.exec_params(<<~SQL, stream.deconstruct).to_a.map { _1['global_position'] }
          DELETE FROM events WHERE context = $1 AND stream_name = $2 AND stream_id = $3 RETURNING global_position
        SQL
        global_positions.each_slice(EVENT_INDEXES_TO_REMOVE_PER_QUERY) do |slice|
          total_removed += conn.exec_params(<<~SQL, [slice]).cmd_tuples
            DELETE FROM events_global_index WHERE global_position = ANY($1)
          SQL
        end
      end
      total_removed
    end

    # @param event [PgEventstore::Event]
    # @return [Integer] number of deleted events
    def delete_event(event)
      connection.with do |conn|
        conn.exec_params(<<~SQL, [event.stream.context, event.stream.stream_name, event.type, event.global_position])
          DELETE FROM events WHERE context = $1 AND stream_name = $2 AND type = $3 AND global_position = $4;
          DELETE FROM events_global_index WHERE global_position = $4;
        SQL
      end.cmd_tuples
    end

    # @param stream [PgEventstore::Stream]
    # @param after_revision [Integer]
    # @return [void]
    def adjust_stream_revisions(stream, after_revision)
      connection.with do |conn|
        conn.exec_params(<<~SQL, [stream.context, stream.stream_name, stream.stream_id, after_revision])
          UPDATE events SET stream_revision = stream_revision - 1
            WHERE context = $1 AND stream_name = $2
              AND stream_id = $3 AND stream_revision > $4
        SQL
      end
      stream_index = streams_global_index_queries.find_by(stream)
      new_revision = stream_index['stream_revision'] - 1
      if new_revision == Stream::NON_EXISTING_STREAM_REVISION
        streams_global_index_queries.delete(stream)
      else
        streams_global_index_queries.update_revision(stream_index['id'], stream_revision: new_revision)
      end
    end

    # @param stream [PgEventstore::Stream]
    # @param after_revision [Integer]
    # @return [Integer]
    def events_to_lock_count(stream, after_revision)
      stream_index = streams_global_index_queries.find_by(stream)
      stream_index['stream_revision'] - after_revision
    end

    # @param event [PgEventstore::Event]
    # @return [PgEventstore::Event]
    def reload_event(event)
      event_attrs = connection.with do |conn|
        conn.exec_params(<<~SQL, [event.stream&.context, event.stream&.stream_name, event.type, event.global_position])
          SELECT * FROM events WHERE context = $1 AND stream_name = $2 AND type = $3 AND global_position = $4 LIMIT 1
        SQL
      end.to_a.first
      return unless event_attrs

      basic_deserializer.deserialize(event_attrs)
    end

    private

    # @return [PgEventstore::EventDeserializer]
    def basic_deserializer
      EventDeserializer.new([], ->(_event_type) { Event })
    end

    def streams_global_index_queries
      StreamsGlobalIndexQueries.new(connection, QueryStrategy::Foreground.new(connection))
    end
  end
end

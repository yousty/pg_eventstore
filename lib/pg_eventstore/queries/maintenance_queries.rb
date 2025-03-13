# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class MaintenanceQueries
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
      connection.with do |conn|
        conn.exec_params(<<~SQL, stream.deconstruct)
          DELETE FROM events WHERE context = $1 AND stream_name = $2 AND stream_id = $3
        SQL
      end.cmd_tuples
    end

    # @param event [PgEventstore::Event]
    # @return [Integer] number of deleted events
    def delete_event(event)
      connection.with do |conn|
        conn.exec_params(<<~SQL, [event.stream.context, event.stream.stream_name, event.type, event.global_position])
          DELETE FROM events WHERE context = $1 AND stream_name = $2 AND type = $3 AND global_position = $4
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
    end

    # @param stream [PgEventstore::Stream]
    # @param after_revision [Integer]
    # @return [Integer]
    def events_to_lock_count(stream, after_revision)
      connection.with do |conn|
        conn.exec_params(<<~SQL, [*stream.deconstruct, after_revision])
          EXPLAIN SELECT * FROM events
                    WHERE context = $1 AND stream_name = $2 AND stream_id = $3 AND stream_revision > $4
        SQL
      end.to_a.first['QUERY PLAN'].match(/rows=(\d+)/)[1].to_i
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
  end
end

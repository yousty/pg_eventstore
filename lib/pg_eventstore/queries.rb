# frozen_string_literal: true

module PgEventstore
  class Queries
    attr_reader :connection, :serializer, :deserializer
    private :connection, :serializer, :deserializer

    # @param connection [PgEventstore::Connection]
    # @param serializer [PgEventstore::EventSerializer]
    # @param deserializer [PgEventstore::PgresultDeserializer]
    def initialize(connection, serializer, deserializer)
      @connection = connection
      @serializer = serializer
      @deserializer = deserializer
    end

    # @param stream_to_lock [PgEventstore::Stream, nil]
    # @return [void]
    def transaction(stream_to_lock = nil)
      connection.with do |conn|
        # We are inside a transaction already - no need to start another one
        if [PG::PQTRANS_ACTIVE, PG::PQTRANS_INTRANS].include?(conn.transaction_status)
          conn.exec_params("SELECT pg_advisory_xact_lock($1)", [stream_to_lock.lock_id]) if stream_to_lock
          next yield
        end

        conn.transaction do
          conn.exec_params("SELECT pg_advisory_xact_lock($1)", [stream_to_lock.lock_id]) if stream_to_lock
          yield
        end
      end
    end

    # @param stream [PgEventstore::Stream]
    # @return [PgEventstore::Event, nil]
    def last_stream_event(stream)
      pgresult = connection.with do |conn|
        sql = <<~SQL
          SELECT * FROM events WHERE context = $1 AND stream_name = $2 AND stream_id = $3 
            ORDER BY global_position 
            DESC LIMIT 1
        SQL
        conn.exec_params(sql, stream.to_a)
      end
      deserializer.deserialize_one(pgresult)
    end

    # @return [PgEventstore::Event, nil]
    def last_all_stream_event
      pgresult = connection.with do |conn|
        sql = <<~SQL
          SELECT * FROM events ORDER BY global_position DESC LIMIT 1
        SQL
        conn.exec_params(sql)
      end
      deserializer.deserialize_one(pgresult)
    end

    # @param event [PgEventstore::Event]
    # @return [PgEventstore::Event]
    def insert(event)
      sql = <<~SQL
        INSERT INTO events (type, data, metadata, context, stream_name, stream_id, stream_revision) 
          VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *
      SQL
      pgresult = connection.with do |conn|
        conn.exec_params(sql, [event.type, event.data, event.metadata, *event.stream, event.stream_revision])
      end
      deserializer.without_middlewares.deserialize_one(pgresult)
    end
  end
end

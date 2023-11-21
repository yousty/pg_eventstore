# frozen_string_literal: true

require_relative 'queries/events_filtering_query'

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
      sql = <<~SQL
        SELECT * FROM events WHERE context = $1 AND stream_name = $2 AND stream_id = $3 
          ORDER BY global_position DESC
          LIMIT 1
      SQL
      pgresult = connection.with do |conn|
        conn.exec_params(sql, stream.to_a)
      end
      deserializer.deserialize_one(pgresult)
    end

    # @return [PgEventstore::Event, nil]
    def last_all_stream_event
      sql = <<~SQL
        SELECT * FROM events ORDER BY global_position DESC LIMIT 1
      SQL
      pgresult = connection.with do |conn|
        conn.exec_params(sql)
      end
      deserializer.deserialize_one(pgresult)
    end


    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @return [Array<PgEventstore::Event>]
    def stream_events(stream, options)
      exec_params = events_filtering_query(stream, options).to_exec_params
      pgresult = connection.with do |conn|
        conn.exec_params(*exec_params)
      end
      deserializer.deserialize_many(pgresult)
    end

    # @param event [PgEventstore::Event]
    # @return [PgEventstore::Event]
    def insert(event)
      insert_map = %w[type data metadata context stream_name stream_id stream_revision]
      insert_map.push('id') if event.id
      sql = <<~SQL
        INSERT INTO events (#{insert_map.join(', ')}) 
          VALUES (#{(1..insert_map.size).map { |n| "$#{n}" }.join(', ')}) RETURNING *
      SQL
      pgresult = connection.with do |conn|
        conn.exec_params(sql, insert_map.map { |attr| event.public_send(attr) })
      end
      deserializer.without_middlewares.deserialize_one(pgresult)
    end

    private

    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @return [PgEventstore::EventsFilteringQuery]
    def events_filtering_query(stream, options)
      event_filter = EventsFilteringQuery.new
      options in { filter: { event_types: Array => event_types } }
      event_types&.each { |event_type| event_filter.add_event_type(event_type) }
      event_filter.add_limit(options[:max_count])
      event_filter.resolve_links(options[:resolve_link_tos])

      if stream.all_stream?
        options in { filter: { streams: Array => streams } }
        streams&.each { |attrs| event_filter.add_stream(**attrs) }
        event_filter.add_global_position(options[:from_position])
      else
        event_filter.add_stream(**stream)
        event_filter.add_revision(options[:from_revision])
      end

      event_filter
    end
  end
end

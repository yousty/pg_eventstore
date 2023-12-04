# frozen_string_literal: true

require_relative 'query_builders/events_filtering_query'

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

    # @return [void]
    def transaction
      connection.with do |conn|
        # We are inside a transaction already - no need to start another one
        if [PG::PQTRANS_ACTIVE, PG::PQTRANS_INTRANS].include?(conn.transaction_status)
          next yield
        end

        conn.transaction do
          conn.exec("SET TRANSACTION ISOLATION LEVEL SERIALIZABLE")
          yield
        end
      end
    rescue PG::TRSerializationFailure, PG::TRDeadlockDetected => e
      retry if e.connection.transaction_status == PG::PQTRANS_IDLE
      raise
    end

    # Finds a stream in the database by the given Stream object
    # @param stream [PgEventstore::Stream]
    # @return [PgEventstore::Stream, nil] persisted stream
    def find_stream(stream)
      find_sql = <<~SQL
        SELECT * FROM streams WHERE streams.context = $1 AND streams.stream_name = $2 AND streams.stream_id = $3
          LIMIT 1
      SQL
      pgresult = connection.with do |conn|
        conn.exec_params(find_sql, stream.to_a)
      end
      PgEventstore::Stream.new(**pgresult.to_a.first.transform_keys(&:to_sym)) if pgresult.ntuples == 1
    end

    # @param stream [PgEventstore::Stream]
    # @return [PgEventstore::RawStream] persisted stream
    def create_stream(stream)
      create_sql = <<~SQL
        INSERT INTO streams (context, stream_name, stream_id) VALUES ($1, $2, $3) RETURNING *
      SQL
      pgresult = connection.with do |conn|
        conn.exec_params(create_sql, stream.to_a)
      end
      PgEventstore::Stream.new(**pgresult.to_a.first.transform_keys(&:to_sym))
    end

    # @return [PgEventstore::Stream] persisted stream
    def find_or_create_stream(stream)
      find_stream(stream) || create_stream(stream)
    end

    # Fetches last event of the given stream id. Middlewares are not applied.
    # @param stream [PgEventstore::Stream] persisted stream
    # @return [PgEventstore::Event, nil]
    def last_event(stream)
      sql = <<~SQL
        SELECT * FROM events WHERE events.stream_id = $1 ORDER BY events.stream_revision DESC LIMIT 1
      SQL
      pgresult = connection.with do |conn|
        conn.exec_params(sql, [stream.id])
      end
      deserializer.without_middlewares.deserialize_one(pgresult)&.tap do |event|
        event.stream = stream
      end
    end

    # @see PgEventstore::Client#read for more info
    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @return [Array<PgEventstore::Event>]
    def stream_events(stream, options)
      exec_params = events_filtering_builder(stream, options).to_exec_params
      pgresult = connection.with do |conn|
        conn.exec_params(*exec_params)
      end
      deserializer.deserialize_many(pgresult)
    end

    # @param stream [PgEventstore::Stream] persisted stream
    # @param event [PgEventstore::Event]
    # @return [PgEventstore::Event]
    def insert(stream, event)
      serializer.serialize(event)

      attributes = event.options_hash.slice(:id, :type, :data, :metadata, :stream_revision, :link_id).compact
      attributes[:stream_id] = stream.id

      sql = <<~SQL
        INSERT INTO events (#{attributes.keys.join(', ')}) 
          VALUES (#{(1..attributes.values.size).map { |n| "$#{n}" }.join(', ')}) 
          RETURNING *
      SQL

      pgresult = connection.with do |conn|
        conn.exec_params(sql, attributes.values)
      end
      deserializer.without_middlewares.deserialize_one(pgresult).tap do |persisted_event|
        persisted_event.stream = stream
      end
    end

    private

    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @param offset [Integer]
    # @return [PgEventstore::EventsFilteringQuery]
    def events_filtering_builder(stream, options, offset: 0)
      event_filter = QueryBuilders::EventsFiltering.new
      options in { filter: { event_types: Array => event_types } }
      event_filter.add_event_types(event_types)
      event_filter.add_limit(options[:max_count])
      event_filter.add_offset(offset)
      event_filter.resolve_links(options[:resolve_link_tos])

      if stream.all_stream?
        options in { filter: { streams: Array => streams } }
        streams&.each { |attrs| event_filter.add_stream_attrs(**attrs) }
        event_filter.add_global_position(options[:from_position])
        event_filter.add_all_stream_direction(options[:direction])
      else
        event_filter.add_stream(stream)
        event_filter.add_revision(options[:from_revision])
        event_filter.add_stream_direction(options[:direction])
      end
      event_filter
    end
  end
end

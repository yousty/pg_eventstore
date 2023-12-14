# frozen_string_literal: true

require_relative 'query_builders/events_filtering_query'

module PgEventstore
  # @!visibility private
  class Queries
    attr_reader :connection, :serializer, :deserializer
    private :connection, :serializer, :deserializer

    # @param connection [PgEventstore::Connection]
    # @param serializer [PgEventstore::EventSerializer]
    # @param deserializer [PgEventstore::PgResultDeserializer]
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
      retry if [PG::PQTRANS_IDLE, PG::PQTRANS_UNKNOWN].include?(e.connection.transaction_status)
      raise
    end

    # Finds a stream in the database by the given Stream object
    # @param stream [PgEventstore::Stream]
    # @return [PgEventstore::Stream, nil] persisted stream
    def find_stream(stream)
      builder =
        SQLBuilder.new.
          from('streams').
          where('streams.context = ? AND streams.stream_name = ? AND streams.stream_id = ?', *stream.to_a).
          limit(1)
      pg_result = connection.with do |conn|
        conn.exec_params(*builder.to_exec_params)
      end
      PgEventstore::Stream.new(**pg_result.to_a.first.transform_keys(&:to_sym)) if pg_result.ntuples == 1
    end

    # @param stream [PgEventstore::Stream]
    # @return [PgEventstore::RawStream] persisted stream
    def create_stream(stream)
      create_sql = <<~SQL
        INSERT INTO streams (context, stream_name, stream_id) VALUES ($1, $2, $3) RETURNING *
      SQL
      pg_result = connection.with do |conn|
        conn.exec_params(create_sql, stream.to_a)
      end
      PgEventstore::Stream.new(**pg_result.to_a.first.transform_keys(&:to_sym))
    end

    # @return [PgEventstore::Stream] persisted stream
    def find_or_create_stream(stream)
      find_stream(stream) || create_stream(stream)
    end

    # @see PgEventstore::Client#read for more info
    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @return [Array<PgEventstore::Event>]
    def stream_events(stream, options)
      exec_params = events_filtering(stream, options).to_exec_params
      pg_result = connection.with do |conn|
        conn.exec_params(*exec_params)
      end
      deserializer.deserialize_many(pg_result)
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

      pg_result = connection.with do |conn|
        conn.exec_params(sql, attributes.values)
      end
      deserializer.without_middlewares.deserialize_one(pg_result).tap do |persisted_event|
        persisted_event.stream = stream
      end
    end

    # @param stream [PgEventstore::Stream] persisted stream
    # @return [void]
    def update_stream_revision(stream, revision)
      connection.with do |conn|
        conn.exec_params(<<~SQL, [revision, stream.id])
          UPDATE streams SET stream_revision = $1 WHERE id = $2
        SQL
      end
    end

    private

    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @param offset [Integer]
    # @return [PgEventstore::EventsFilteringQuery]
    def events_filtering(stream, options, offset: 0)
      return QueryBuilders::EventsFiltering.all_stream_filtering(options, offset: offset) if stream.all_stream?

      QueryBuilders::EventsFiltering.specific_stream_filtering(stream, options, offset: offset)
    end
  end
end

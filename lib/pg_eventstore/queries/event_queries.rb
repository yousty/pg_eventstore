# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventQueries
    attr_reader :connection, :serializer, :deserializer
    private :connection, :serializer, :deserializer

    # @param connection [PgEventstore::Connection]
    # @param serializer [PgEventstore::EventSerializer]
    # @param deserializer [PgEventstore::EventDeserializer]
    def initialize(connection, serializer, deserializer)
      @connection = connection
      @serializer = serializer
      @deserializer = deserializer
    end

    # @see PgEventstore::Client#read for more info
    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @return [Array<PgEventstore::Event>]
    def stream_events(stream, options)
      options = event_type_queries.include_event_types_ids(options)
      exec_params = events_filtering(stream, options).to_exec_params
      pg_result = connection.with do |conn|
        conn.exec_params(*exec_params)
      end
      deserializer.deserialize_pg_result(pg_result)
    end

    # @param stream [PgEventstore::Stream] persisted stream
    # @param event [PgEventstore::Event]
    # @return [PgEventstore::Event]
    def insert(stream, event)
      serializer.serialize(event)

      attributes = event.options_hash.slice(:id, :data, :metadata, :stream_revision, :link_id).compact
      attributes[:stream_id] = stream.id
      attributes[:event_type_id] = event_type_queries.find_or_create_type(event.type)

      sql = <<~SQL
        INSERT INTO events (#{attributes.keys.join(', ')}) 
          VALUES (#{Utils.positional_vars(attributes.values)}) 
          RETURNING *, $#{attributes.values.size + 1} as type
      SQL

      pg_result = connection.with do |conn|
        conn.exec_params(sql, [*attributes.values, event.type])
      end
      deserializer.without_middlewares.deserialize_one_pg_result(pg_result).tap do |persisted_event|
        persisted_event.stream = stream
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

    # @return [PgEventstore::EventTypeQueries]
    def event_type_queries
      EventTypeQueries.new(connection)
    end
  end
end

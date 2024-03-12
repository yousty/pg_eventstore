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

    # @param id [String, nil]
    # @return [Boolean]
    def event_exists?(id)
      return false if id.nil?

      sql_builder = SQLBuilder.new.select('1 as exists').from('events').where('id = ?', id).limit(1)
      connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end.to_a.dig(0, 'exists') == 1
    end

    # @param stream [PgEventstore::Stream]
    # @return [Integer, nil]
    def stream_revision(stream)
      sql_builder = SQLBuilder.new.from('events').select('stream_revision').
        where('context = ? and stream_name = ? and stream_id = ?', *stream.to_a).
        order('stream_revision DESC').
        limit(1)
      connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end.to_a.dig(0, 'stream_revision')
    end

    # @see PgEventstore::Client#read for more info
    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @return [Array<PgEventstore::Event>]
    def stream_events(stream, options)
      exec_params = events_filtering(stream, options).to_exec_params
      raw_events = connection.with do |conn|
        conn.exec_params(*exec_params)
      end.to_a
      deserializer.deserialize_many(raw_events)
    end

    # @param stream [PgEventstore::Stream]
    # @param events [Array<PgEventstore::Event>]
    # @return [PgEventstore::Event]
    def insert(stream, events)
      sql_rows_for_insert, values = prepared_statements(stream, events)
      columns = %w[id data metadata stream_revision link_id type context stream_name stream_id]

      sql = <<~SQL
        INSERT INTO events (#{columns.join(', ')}) 
          VALUES #{sql_rows_for_insert.join(", ")} 
          RETURNING *
      SQL

      connection.with do |conn|
        conn.exec_params(sql, values)
      end.map do |raw_event|
        deserializer.without_middlewares.deserialize(raw_event)
      end
    end

    private

    # @param stream [PgEventstore::Stream]
    # @param events [Array<PgEventstore::Event>]
    # @return [Array<Array<String>, Array<Object>>]
    def prepared_statements(stream, events)
      positional_counter = 1
      values = []
      sql_rows_for_insert = events.map do |event|
        event = serializer.serialize(event)
        attributes = event.options_hash.slice(:id, :data, :metadata, :stream_revision, :link_id, :type)

        attributes = attributes.merge(stream.to_hash)
        prepared = attributes.values.map do |value|
          if value.nil?
            'DEFAULT'
          else
            "$#{positional_counter}".tap do
              values.push(value)
              positional_counter += 1
            end
          end
        end
        "(#{prepared.join(',')})"
      end
      [sql_rows_for_insert, values]
    end

    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @return [PgEventstore::EventsFilteringQuery]
    def events_filtering(stream, options)
      return QueryBuilders::EventsFiltering.all_stream_filtering(options) if stream.all_stream?

      QueryBuilders::EventsFiltering.specific_stream_filtering(stream, options)
    end
  end
end

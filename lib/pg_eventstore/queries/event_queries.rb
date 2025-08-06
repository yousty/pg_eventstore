# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    # @!attribute serializer
    #   @return [PgEventstore::EventSerializer]
    attr_reader :serializer
    # @!attribute deserializer
    #   @return [PgEventstore::EventDeserializer]
    attr_reader :deserializer
    private :connection, :serializer, :deserializer

    # @param connection [PgEventstore::Connection]
    # @param serializer [PgEventstore::EventSerializer]
    # @param deserializer [PgEventstore::EventDeserializer]
    def initialize(connection, serializer, deserializer)
      @connection = connection
      @serializer = serializer
      @deserializer = deserializer
    end

    # @param event [PgEventstore::Event]
    # @return [Boolean]
    def event_exists?(event)
      return false if event.id.nil? || event.stream.nil?

      sql_builder = SQLBuilder.new.select('1 as exists').from('events').where('id = ?', event.id).limit(1)
      sql_builder.where(
        'context = ? and stream_name = ? and type = ?', event.stream.context, event.stream.stream_name, event.type
      )
      connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end.to_a.dig(0, 'exists') == 1
    end

    # Takes an array of potentially persisted events and loads their ids from db. Those ids can be later used to check
    # whether events are actually existing events.
    # @param events [Array<PgEventstore::Event>]
    # @return [Array<String>]
    def ids_from_db(events)
      sql_builder = SQLBuilder.new.from('events').select('id')
      partition_attrs = events.map { |event| [event.stream&.context, event.stream&.stream_name, event.type] }.uniq
      partition_attrs.each do |context, stream_name, event_type|
        sql_builder.where_or('context = ? and stream_name = ? and type = ?', context, stream_name, event_type)
      end
      sql_builder.where('id = ANY(?::uuid[])', events.map(&:id))
      raw_events = PgEventstore.connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end.to_a
      raw_events.map { |attrs| attrs['id'] }
    end

    # @param stream [PgEventstore::Stream]
    # @return [Integer, nil]
    def stream_revision(stream)
      sql_builder = SQLBuilder.new.from('events').select('stream_revision')
      sql_builder.where('context = ? and stream_name = ? and stream_id = ?', *stream.to_a)
      sql_builder.order('stream_revision DESC').limit(1)
      connection.with do |conn|
        conn.exec_params(*sql_builder.to_exec_params)
      end.to_a.dig(0, 'stream_revision')
    end

    # @see PgEventstore::Client#read for more info
    # @param stream [PgEventstore::Stream]
    # @param options [Hash]
    # @return [Array<PgEventstore::Event>]
    def stream_events(stream, options)
      exec_params = QueryBuilders::EventsFiltering.events_filtering(stream, options).to_exec_params
      raw_events = connection.with do |conn|
        conn.exec_params(*exec_params)
      end.to_a
      raw_events = links_resolver.resolve(raw_events) if options[:resolve_link_tos]
      deserializer.deserialize_many(raw_events)
    end

    # @param stream [PgEventstore::Stream]
    # @param events [Array<PgEventstore::Event>]
    # @return [Array<PgEventstore::Event>]
    def insert(stream, events)
      sql_rows_for_insert, values = prepared_statements(stream, events)
      columns = %w[id data metadata stream_revision link_id link_partition_id type context stream_name stream_id]

      sql = <<~SQL
        INSERT INTO events (#{columns.join(', ')})
          VALUES #{sql_rows_for_insert.join(', ')}
          RETURNING *
      SQL

      raw_events = connection.with do |conn|
        conn.exec_params(sql, values)
      end
      raw_events.map do |raw_event|
        deserializer.without_middlewares.deserialize(raw_event)
      end
    end

    # @param stream [PgEventstore::Stream]
    # @param options_by_event_type [Array<Hash>] a set of options per an event type
    # @param options [Hash]
    # @option options [Boolean] :resolve_link_tos
    # @return [Array<PgEventstore::Event>]
    def grouped_events(stream, options_by_event_type, **options)
      builders = options_by_event_type.map do |filter|
        QueryBuilders::EventsFiltering.events_filtering(stream, filter)
      end
      final_builder = SQLBuilder.union_builders(builders.map(&:to_sql_builder))

      raw_events = connection.with do |conn|
        conn.exec_params(*final_builder.to_exec_params)
      end.to_a
      raw_events = links_resolver.resolve(raw_events) if options[:resolve_link_tos]
      deserializer.deserialize_many(raw_events)
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
        attributes = event.options_hash.slice(
          :id, :data, :metadata, :stream_revision, :link_id, :link_partition_id, :type
        )

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

    # @return [PgEventstore::LinksResolver]
    def links_resolver
      LinksResolver.new(connection)
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventTypeQueries
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param type [String]
    # @return [Integer] event type's id
    def find_or_create_type(type)
      find_type(type) || create_type(type)
    end

    # @param type [String]
    # @return [Integer, nil] event type's id
    def find_type(type)
      connection.with do |conn|
        conn.exec_params('SELECT id FROM event_types WHERE type = $1', [type])
      end.to_a.dig(0, 'id')
    end

    # @param type [String]
    # @return [Integer] event type's id
    def create_type(type)
      connection.with do |conn|
        conn.exec_params('INSERT INTO event_types (type) VALUES ($1) RETURNING id', [type])
      end.to_a.dig(0, 'id')
    end

    # @param types [Array<String>]
    # @return [Array<Integer, nil>]
    def find_event_types(types)
      connection.with do |conn|
        conn.exec_params(<<~SQL, [types])
          SELECT event_types.id, types.type
            FROM event_types 
            RIGHT JOIN (
              SELECT unnest($1::varchar[]) type
            ) types ON types.type = event_types.type
        SQL
      end.to_a.map { |attrs| attrs['id'] }
    end
  end
end

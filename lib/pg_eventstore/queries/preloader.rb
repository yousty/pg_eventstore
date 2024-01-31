# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class Preloader
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param raw_events [Array<Hash>]
    # @return [Array<Hash>]
    def preload_related_objects(raw_events)
      streams = stream_queries.find_by_ids(raw_events.map { _1['stream_id'] }).map { [_1['id'], _1] }.to_h
      types = event_type_queries.find_by_ids(raw_events.map { _1['event_type_id'] }).map { [_1['id'], _1] }.to_h
      raw_events.each do |event|
        event['stream'] = streams[event['stream_id']]
        event['type'] = types[event['event_type_id']]['type']
      end
    end

    private

    # @return [PgEventstore::EventTypeQueries]
    def event_type_queries
      EventTypeQueries.new(connection)
    end

    # @return [PgEventstore::StreamQueries]
    def stream_queries
      StreamQueries.new(connection)
    end
  end
end

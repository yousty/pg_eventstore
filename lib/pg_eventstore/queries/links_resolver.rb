# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class LinksResolver
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param raw_events [Array<Hash>]
    def resolve(raw_events)
      ids = raw_events.map { _1['link_id'] }.compact.uniq
      return raw_events if ids.empty?

      original_events = connection.with do |conn|
        conn.exec_params('select * from events where id = ANY($1::uuid[])', [ids])
      end.to_h { |attrs| [attrs['id'], attrs] }

      raw_events.map do |attrs|
        original_event = original_events[attrs['link_id']]
        next attrs unless original_event

        original_event.merge('link' => attrs).merge(attrs.except(*original_event.keys))
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class MaintenanceQueries
    # @!attribute connection
    #   @return [PgEventstore::Connection]
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
    end

    # @param stream [PgEventstore::Stream]
    # @return [Integer] number of deleted events of the given stream
    def delete_stream(stream)
      connection.with do |conn|
        conn.exec_params(<<~SQL, stream.deconstruct)
          DELETE FROM events WHERE context = $1 AND stream_name = $2 AND stream_id = $3
        SQL
      end.cmd_tuples
    end
  end
end

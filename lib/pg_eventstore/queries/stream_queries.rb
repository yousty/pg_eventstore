# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class StreamQueries
    attr_reader :connection
    private :connection

    # @param connection [PgEventstore::Connection]
    def initialize(connection)
      @connection = connection
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
      deserialize(pg_result) if pg_result.ntuples == 1
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
      deserialize(pg_result)
    end

    # @return [PgEventstore::Stream] persisted stream
    def find_or_create_stream(stream)
      find_stream(stream) || create_stream(stream)
    end

    # @param stream [PgEventstore::Stream] persisted stream
    # @return [PgEventstore::Stream]
    def update_stream_revision(stream, revision)
      connection.with do |conn|
        conn.exec_params(<<~SQL, [revision, stream.id])
          UPDATE streams SET stream_revision = $1 WHERE id = $2
        SQL
      end
      stream.stream_revision = revision
      stream
    end

    private

    # @param pg_result [PG::Result]
    # @return [PgEventstore::Stream, nil]
    def deserialize(pg_result)
      PgEventstore::Stream.new(**pg_result.to_a.first.transform_keys(&:to_sym))
    end
  end
end

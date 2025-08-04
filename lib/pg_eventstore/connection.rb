# frozen_string_literal: true

require 'pg'
require 'pg/basic_type_map_for_results'
require 'pg/basic_type_map_for_queries'
require 'connection_pool'
require_relative 'pg_connection'

module PgEventstore
  class Connection
    # Starting from ruby v3.1 ConnectionPool closes connections after forking by default. For ruby v3 we need this patch
    # to correctly reload the ConnectionPool. Otherwise the same connection will leak into another process which will
    # result in disaster.
    # @!visibility private
    module Ruby30Patch
      def initialize(**)
        @current_pid = Process.pid
        @mutext = Mutex.new
        super
      end

      def with(&blk)
        reload_after_fork
        super
      end

      private

      def reload_after_fork
        return if @current_pid == Process.pid

        @mutext.synchronize do
          return if @current_pid == Process.pid

          @pool.reload(&:close)
          @current_pid = Process.pid
        end
      end
    end

    # @!attribute uri
    #   @return [String]
    attr_reader :uri
    # @!attribute pool_size
    #   @return [Integer]
    attr_reader :pool_size
    # @!attribute pool_timeout
    #   @return [Integer]
    attr_reader :pool_timeout
    private :uri, :pool_size, :pool_timeout

    # @param uri [String] PostgreSQL connection URI.
    #   Example: "postgresql://postgres:postgres@localhost:5432/eventstore"
    # @param pool_size [Integer] Connection pool size
    # @param pool_timeout [Integer] Connection pool timeout in seconds
    def initialize(uri:, pool_size: 5, pool_timeout: 5)
      @uri = uri
      @pool_size = pool_size
      @pool_timeout = pool_timeout
      init_pool
    end

    # A shorthand from ConnectionPool#with.
    # @yieldparam connection [PG::Connection] PostgreSQL connection instance
    # @return [Object] a value of a given block
    def with(&)
      should_retry = true
      @pool.with do |conn|
        yield conn
      rescue PG::ConnectionBad, PG::UnableToSend
        # Recover a connection after fork or when we lost a connection to PostgreSQL. We retry only once and without any
        # delay.
        conn.sync_reset
        raise unless should_retry

        should_retry = false
        retry
      end
    end

    # @return [void]
    def shutdown
      @pool.shutdown(&:close)
    end

    private

    # @return [ConnectionPool]
    # rubocop:disable Naming/MemoizedInstanceVariableName
    def init_pool
      @pool ||= ConnectionPool.new(size: pool_size, timeout: pool_timeout) do
        PgConnection.new(uri).tap do |conn|
          conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn, registry: pg_type_registry)
          conn.type_map_for_queries = PG::BasicTypeMapForQueries.new(conn, registry: pg_type_registry)
        end
      end
    end
    # rubocop:enable Naming/MemoizedInstanceVariableName

    # @return [PG::BasicTypeRegistry]
    def pg_type_registry
      registry = PG::BasicTypeRegistry.new.register_default_types
      # 0 means that the pg value format is a text(1 for binary)
      registry.alias_type(0, 'uuid', 'text')
      registry.register_type 0, 'timestamp', PG::TextEncoder::TimestampUtc, PG::TextDecoder::TimestampUtc
      registry
    end
  end
end

if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.1')
  PgEventstore::Connection.prepend(PgEventstore::Connection::Ruby30Patch)
end

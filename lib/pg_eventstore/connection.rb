# frozen_string_literal: true

require 'pg'
require 'pg/basic_type_map_for_results'
require 'pg/basic_type_map_for_queries'
require 'connection_pool'

module PgEventstore
  class Connection
    attr_reader :uri, :pool_size, :pool_timeout, :pool
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

    def with(&blk)
      pool.with(&blk)
    end

    # @return [String]
    def db_name
      dbname = URI.parse(uri).path&.delete('/')
      return 'postgres' if dbname == '' || dbname.nil?
      dbname
    end

    # @return [String]
    def user
      user = URI.parse(uri).user
      return 'postgres' if user == '' || user.nil?
      user
    end

    private

    # @return [ConnectionPool]
    def init_pool
      @pool ||= ConnectionPool.new(size: pool_size, timeout: pool_timeout) do
        PG::Connection.new(uri).tap do |conn|
          conn.type_map_for_results = PG::BasicTypeMapForResults.new(conn, registry: pg_type_registry)
          conn.type_map_for_queries = PG::BasicTypeMapForQueries.new(conn)
          # conn.trace($stdout) # logs
        end
      end
    end

    private

    def pg_type_registry
      registry = PG::BasicTypeRegistry.new.register_default_types
      # 0 means that the pg value format is a text(1 for binary)
      registry.alias_type(0, 'uuid', 'text')
      registry
    end
  end
end

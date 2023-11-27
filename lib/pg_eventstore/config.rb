# frozen_string_literal: true

module PgEventstore
  class Config
    include Extensions::OptionsExtension

    attr_reader :name

    # PostgreSQL connection URI docs https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING-URIS
    option(:pg_uri) { 'postgresql://postgres:postgres@localhost:5432/eventstore' }
    option(:per_page) { 1000 }
    option(:middlewares) { [] }
    # Object that responds to #call. Should accept a string and return a class
    option(:event_class_resolver) { EventClassResolver.new }
    option(:connection_pool_size) { 5 }
    option(:connection_pool_timeout) { 5 } # seconds

    # @param name [Symbol] config's name. Its value matches the appropriate key in PgEventstore.config hash
    def initialize(name:, **options)
      super
      @name = name
    end

    # Computes a value for usage in PgEventstore::Connection
    # @return [Hash]
    def connection_options
      { uri: pg_uri, pool_size: connection_pool_size, pool_timeout: connection_pool_timeout }
    end
  end
end

# frozen_string_literal: true

require_relative 'pg_eventstore/version'
require_relative 'pg_eventstore/extensions/options_extension'
require_relative 'pg_eventstore/event_class_resolver'
require_relative 'pg_eventstore/config'
require_relative 'pg_eventstore/event'
require_relative 'pg_eventstore/stream'
require_relative 'pg_eventstore/client'
require_relative 'pg_eventstore/connection'
require_relative 'pg_eventstore/errors'

module PgEventstore
  class << self
    attr_reader :mutex
    private :mutex

    # @param name [Symbol]
    def configure(name: :default)
      @config[name] ||= Config.new(name:)

      yield(@config[name]) if block_given?
    end

    # @param name [Symbol, String]
    # @return [PgEventstore::Config]
    def config(name = :default)
      return @config[name] if @config[name]

      error_message = <<~TEXT
        Could not find #{name.inspect} config. You can define it like this:
        PgEventstore.configure(name: #{name.inspect}) do |config|
          # your config goes here
        end
      TEXT
      raise error_message
    end

    # @param name [Symbol, String]
    # @return [PgEventstore::Connection]
    def connection(name = :default)
      mutex.synchronize do
        @connection[name] ||= Connection.new(**config(name).connection_options)
      end
    end

    # @param name [Symbol, String]
    # @return [PgEventstore::Client]
    def client(name = :default)
      Client.new(config(name))
    end

    def logger
      @logger
    end

    def logger=(logger)
      @logger = logger
    end

    private

    # @return [void]
    def init_default_values
      @config = { default: Config.new(name: :default) }
      @connection = {}
      @mutex = Thread::Mutex.new
    end
  end
  init_default_values
end

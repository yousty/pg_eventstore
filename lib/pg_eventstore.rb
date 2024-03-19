# frozen_string_literal: true

require_relative 'pg_eventstore/version'
require_relative 'pg_eventstore/utils'
require_relative 'pg_eventstore/callbacks'
require_relative 'pg_eventstore/extensions/options_extension'
require_relative 'pg_eventstore/extensions/callbacks_extension'
require_relative 'pg_eventstore/extensions/using_connection_extension'
require_relative 'pg_eventstore/event_class_resolver'
require_relative 'pg_eventstore/config'
require_relative 'pg_eventstore/event'
require_relative 'pg_eventstore/stream'
require_relative 'pg_eventstore/client'
require_relative 'pg_eventstore/connection'
require_relative 'pg_eventstore/errors'
require_relative 'pg_eventstore/middleware'
require_relative 'pg_eventstore/subscriptions/subscriptions_manager'

module PgEventstore
  class << self
    attr_reader :mutex
    private :mutex

    # Creates a Config if not exists and yields it to the given block.
    # @param name [Symbol] a name to assign to a config
    # @return [Object] a result of the given block
    def configure(name: :default)
      mutex.synchronize do
        @config[name] ||= Config.new(name: name)
        connection_config_was = @config[name].connection_options

        yield(@config[name]).tap do
          next if connection_config_was == @config[name].connection_options

          # Reset the connection if user decided to reconfigure connection's options
          @connection.delete(name)
        end
      end
    end

    # @return [Array<Symbol>]
    def available_configs
      @config.keys
    end

    # @param name [Symbol]
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

    # Look ups and returns a Connection, based on the given config. If not exists - it creates one. This operation is a
    # thread-safe
    # @param name [Symbol]
    # @return [PgEventstore::Connection]
    def connection(name = :default)
      mutex.synchronize do
        @connection[name] ||= Connection.new(**config(name).connection_options)
      end
    end

    # @param config_name [Symbol]
    # @param subscription_set [String]
    # @param max_retries [Integer, nil] max number of retries of failed SubscriptionsSet
    # @param retries_interval [Integer, nil] a delay between retries of failed SubscriptionsSet
    # @return [PgEventstore::SubscriptionManager]
    def subscriptions_manager(config_name = :default, subscription_set:, max_retries: nil, retries_interval: nil)
      SubscriptionsManager.new(
        config: config(config_name),
        set_name: subscription_set,
        max_retries: max_retries,
        retries_interval: retries_interval
      )
    end

    # @param name [Symbol]
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
    def init_variables
      @config = { default: Config.new(name: :default) }
      @connection = {}
      @mutex = Thread::Mutex.new
    end
  end
  init_variables
end

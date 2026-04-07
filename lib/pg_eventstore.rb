# frozen_string_literal: true

require_relative 'pg_eventstore/version'
require_relative 'pg_eventstore/utils'
require_relative 'pg_eventstore/callbacks'
require_relative 'pg_eventstore/extensions/options_extension'
require_relative 'pg_eventstore/extensions/callbacks_extension'
require_relative 'pg_eventstore/extensions/callback_handlers_extension'
require_relative 'pg_eventstore/extensions/using_connection_extension'
require_relative 'pg_eventstore/event_class_resolver'
require_relative 'pg_eventstore/basic_config'
require_relative 'pg_eventstore/config'
require_relative 'pg_eventstore/partition'
require_relative 'pg_eventstore/event'
require_relative 'pg_eventstore/stream'
require_relative 'pg_eventstore/commands'
require_relative 'pg_eventstore/queries'
require_relative 'pg_eventstore/client'
require_relative 'pg_eventstore/maintenance'
require_relative 'pg_eventstore/connection'
require_relative 'pg_eventstore/errors'
require_relative 'pg_eventstore/middleware'
require_relative 'pg_eventstore/subscriptions/subscriptions_manager'
require_relative 'pg_eventstore/extensions/acts_as_configurable'

module PgEventstore
  extend Extensions::ActsAsConfigurable

  acts_as_configurable(config_class: Config)

  class << self
    # @return [Logger, nil]
    attr_accessor :logger

    # @param config_name [Symbol]
    # @param subscription_set [String]
    # @param max_retries [Integer, nil] max number of retries of failed SubscriptionsSet
    # @param retries_interval [Integer, nil] a delay between retries of failed SubscriptionsSet
    # @param force_lock [Boolean] whether to force-lock subscriptions
    # @return [PgEventstore::SubscriptionsManager]
    def subscriptions_manager(config_name = DEFAULT_CONFIG, subscription_set:, max_retries: nil, retries_interval: nil,
                              force_lock: false)
      SubscriptionsManager.new(
        config: config(config_name),
        set_name: subscription_set,
        max_retries:,
        retries_interval:,
        force_lock:
      )
    end

    # @param name [Symbol]
    # @return [PgEventstore::Client]
    def client(name = DEFAULT_CONFIG)
      Client.new(config(name))
    end

    # @param name [Symbol]
    # @return [PgEventstore::Maintenance]
    def maintenance(name = DEFAULT_CONFIG)
      Maintenance.new(config(name))
    end

    private

    # @param config [Config]
    # @return [Hash]
    def connection_options(config)
      { uri: config.pg_uri, pool_size: config.connection_pool_size, pool_timeout: config.connection_pool_timeout }
    end
  end
end

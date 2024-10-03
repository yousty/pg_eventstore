# frozen_string_literal: true

module PgEventstore
  class Config
    include Extensions::OptionsExtension

    attr_reader :name

    # @!attribute pg_uri
    #   @return [String] PostgreSQL connection URI docs
    #     https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING-URIS
    option(:pg_uri) do
      ENV.fetch('PG_EVENTSTORE_URI') { 'postgresql://postgres:postgres@localhost:5432/eventstore' }
    end
    # @!attribute max_count
    #   @return [Integer] Number of events to return in one response when reading from a stream
    option(:max_count) { 1000 }
    # @!attribute middlewares
    #   @return [Hash{Symbol => <#serialize, #deserialize>}] A set of identified(by key) objects that respond to
    #     #serialize and #deserialize
    option(:middlewares) { {} }
    # @!attribute event_class_resolver
    #   @return [#call] A callable object that must accept a string and return a class. It is used when resolving
    #     event's class during event's deserialization process
    option(:event_class_resolver) { EventClassResolver.new }
    # @!attribute connection_pool_size
    #   @return [Integer] Max number of connections per ruby process
    option(:connection_pool_size) { 5 }
    # @!attribute connection_pool_timeout
    #   @return [Integer] Time in seconds to wait for the connection in pool to be released
    option(:connection_pool_timeout) { 5 }
    # @!attribute subscription_pull_interval
    #   @return [Float, Integer] How often Subscription should pull new events, seconds
    option(:subscription_pull_interval) { 1.0 }
    # @!attribute subscription_max_retries
    #   @return [Integer] max number of retries of failed Subscription
    option(:subscription_max_retries) { 5 }
    # @!attribute subscription_retries_interval
    #   @return [Integer] interval in seconds between retries of failed Subscription
    option(:subscription_retries_interval) { 1 }
    # @!attribute subscription_restart_terminator
    #   @return [#call, nil] provide callable object that accepts Subscription object to decide whether to prevent
    #     further Subscription restarts
    option(:subscription_restart_terminator)
    # @!attribute subscriptions_set_max_retries
    #   @return [Integer] max number of retries of failed SubscriptionsSet
    option(:subscriptions_set_max_retries) { 10 }
    # @!attribute subscriptions_set_retries_interval
    #   @return [Integer] interval in seconds between retries of failed SubscriptionsSet
    option(:subscriptions_set_retries_interval) { 1 }
    # @!attribute failed_subscription_notifier
    #   @return [#call, nil] provide callable object that accepts Subscription instance and error. It is useful when you
    #     want to be get notified when your Subscription fails and no longer can be restarted
    option(:failed_subscription_notifier)
    # @!attribute subscription_graceful_shutdown_timeout
    #   @return [Integer] the number of seconds to wait until force-shutdown the subscription during the stop process
    option(:subscription_graceful_shutdown_timeout) { 15 }

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

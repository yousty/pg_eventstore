# frozen_string_literal: true

require 'forwardable'
require_relative 'runner_state'
require_relative 'basic_runner'
require_relative 'subscription'
require_relative 'events_processor'
require_relative 'subscription_handler_performance'
require_relative 'subscription_runner'
require_relative 'subscriptions_set'
require_relative 'subscription_runners_feeder'
require_relative 'subscriptions_set_lifecycle'
require_relative 'subscriptions_lifecycle'
require_relative 'callback_handlers/subscription_feeder_handlers'
require_relative 'callback_handlers/subscription_runner_handlers'
require_relative 'callback_handlers/events_processor_handlers'
require_relative 'callback_handlers/commands_handler_handlers'
require_relative 'subscription_feeder'
require_relative 'extensions/command_class_lookup_extension'
require_relative 'extensions/base_command_extension'
require_relative 'subscription_feeder_commands'
require_relative 'subscription_runner_commands'
require_relative 'queries/subscription_command_queries'
require_relative 'queries/subscription_queries'
require_relative 'queries/subscriptions_set_command_queries'
require_relative 'queries/subscriptions_set_queries'
require_relative 'commands_handler'

module PgEventstore
  # The public Subscriptions API, available to the user.
  class SubscriptionsManager
    extend Forwardable

    class << self
      # @return [PgEventstore::Callbacks]
      def callbacks
        @callbacks ||= Callbacks.new
      end
    end

    # @!attribute config
    #   @return [PgEventstore::Config]
    attr_reader :config
    private :config

    def_delegators :@subscription_feeder, :stop, :running?
    def_delegators :@subscriptions_lifecycle, :force_lock!

    # @param config [PgEventstore::Config]
    # @param set_name [String]
    # @param max_retries [Integer, nil] max number of retries of failed SubscriptionsSet
    # @param retries_interval [Integer, nil] a delay between retries of failed SubscriptionsSet
    # @param force_lock [Boolean] whether to force-lock subscriptions
    def initialize(config:, set_name:, max_retries: nil, retries_interval: nil, force_lock: false)
      @config = config
      @set_name = set_name
      @subscriptions_set_lifecycle = SubscriptionsSetLifecycle.new(
        config_name,
        {
          name: set_name,
          max_restarts_number: max_retries || config.subscriptions_set_max_retries,
          time_between_restarts: retries_interval || config.subscriptions_set_retries_interval
        }
      )
      @subscriptions_lifecycle = SubscriptionsLifecycle.new(
        config_name, @subscriptions_set_lifecycle, force_lock: force_lock
      )
      @subscription_feeder = SubscriptionFeeder.new(
        config_name: config_name,
        subscriptions_set_lifecycle: @subscriptions_set_lifecycle,
        subscriptions_lifecycle: @subscriptions_lifecycle
      )
    end

    # @param subscription_name [String] subscription's name
    # @param handler [#call] subscription's handler
    # @param options [Hash] request options
    # @option options [Integer, Symbol] :from_position a starting subscription position
    # @option options [Boolean] :resolve_link_tos When using projections to create new events you
    #   can set whether the generated events are pointers to existing events. Setting this option to true tells
    #   PgEventstore to return the original event instead a link event.
    # @option options [Hash] :filter provide it to filter events. It works the same way as a :filter option of
    #   {PgEventstore::Client#read} method. Filtering by both - event types and streams are available.
    # @param middlewares [Array<Symbol>, nil] provide a list of middleware names to override a config's middlewares
    # @param pull_interval [Integer, Float] an interval in seconds to determine how often to query new events of the
    #   given subscription.
    # @param max_retries [Integer] max number of retries of failed Subscription
    # @param retries_interval [Integer, Float] a delay between retries of failed Subscription
    # @param restart_terminator [#call, nil] a callable object which is invoked with PgEventstore::Subscription instance
    #   to determine whether restarts should be stopped(true - stops restarts, false - continues restarts)
    # @param failed_subscription_notifier [#call, nil] a callable object which is invoked with
    #   PgEventstore::Subscription instance and error instance after the related subscription died due to error and no
    #   longer can be automatically restarted due to max retries number reached. You can use this hook to send a
    #   notification about failed subscription.
    # @param graceful_shutdown_timeout [integer, Float] the number of seconds to wait until force-shutdown the
    #   subscription during the stop process
    # @return [void]
    def subscribe(subscription_name, handler:, options: {}, middlewares: nil,
                  pull_interval: config.subscription_pull_interval,
                  max_retries: config.subscription_max_retries,
                  retries_interval: config.subscription_retries_interval,
                  restart_terminator: config.subscription_restart_terminator,
                  failed_subscription_notifier: config.failed_subscription_notifier,
                  graceful_shutdown_timeout: config.subscription_graceful_shutdown_timeout)
      subscription = Subscription.using_connection(config.name).new(
        set: @set_name, name: subscription_name, options: options, chunk_query_interval: pull_interval,
        max_restarts_number: max_retries, time_between_restarts: retries_interval
      )
      runner = SubscriptionRunner.new(
        stats: SubscriptionHandlerPerformance.new,
        events_processor: EventsProcessor.new(
          create_raw_event_handler(middlewares, handler), graceful_shutdown_timeout: graceful_shutdown_timeout
        ),
        subscription: subscription,
        restart_terminator: restart_terminator,
        failed_subscription_notifier: failed_subscription_notifier
      )

      @subscriptions_lifecycle.runners.push(runner)
      true
    end

    # @return [Array<PgEventstore::Subscription>]
    def subscriptions
      @subscriptions_lifecycle.subscriptions.map(&:dup)
    end

    # @return [PgEventstore::SubscriptionsSet, nil]
    def subscriptions_set
      @subscriptions_set_lifecycle.subscriptions_set&.dup
    end

    # @return [PgEventstore::BasicRunner]
    # @raise [PgEventstore::SubscriptionAlreadyLockedError]
    def start!
      self.class.callbacks.run_callbacks(:start, self) do
        @subscription_feeder.start
      end
    end

    # @return [PgEventstore::BasicRunner, nil]
    def start
      start!
    rescue PgEventstore::SubscriptionAlreadyLockedError => e
      PgEventstore.logger&.warn(e.message)
      nil
    end

    # @return [Symbol]
    def config_name
      @config.name
    end

    private

    # @param middlewares [Array<Symbol>, nil]
    # @param handler [#call]
    # @return [Proc]
    def create_raw_event_handler(middlewares, handler)
      deserializer = EventDeserializer.new(select_middlewares(middlewares), config.event_class_resolver)
      ->(raw_event) { handler.call(deserializer.deserialize(raw_event)) }
    end

    # @param middlewares [Array, nil]
    # @return [Array<PgEventstore::Middleware>]
    def select_middlewares(middlewares = nil)
      return config.middlewares.values unless middlewares

      config.middlewares.slice(*middlewares).values
    end
  end
end

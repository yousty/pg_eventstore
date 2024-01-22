# frozen_string_literal: true

require 'forwardable'
require_relative 'basic_runner'
require_relative 'subscription'
require_relative 'events_processor'
require_relative 'subscription_handler_performance'
require_relative 'subscription_runner'
require_relative 'runner_state'
require_relative 'subscriptions_set'
require_relative 'subscription_runners_feeder'
require_relative 'subscription_feeder'
require_relative 'commands_handler'

module PgEventstore
  # The public Subscriptions API, available to the user.
  class SubscriptionsManager
    extend Forwardable

    attr_reader :config
    private :config

    def_delegators :@subscription_feeder, :start, :stop, :force_lock!

    # @param config [PgEventstore::Config]
    # @param set_name [String]
    # @param max_retries [Integer, nil] max number of retries of failed SubscriptionsSet
    # @param retries_interval [Integer, nil] a delay between retries of failed SubscriptionsSet
    def initialize(config:, set_name:, max_retries: nil, retries_interval: nil)
      @config = config
      @set_name = set_name
      @subscription_feeder = SubscriptionFeeder.new(
        config_name: config.name,
        set_name: set_name,
        max_retries: max_retries || config.subscriptions_set_max_retries,
        retries_interval: retries_interval || config.subscriptions_set_retries_interval
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
    # @param pull_interval [Integer] an interval in seconds to determine how often to query new events of the given
    #   subscription.
    # @param max_retries [Integer] max number of retries of failed Subscription
    # @param retries_interval [Integer] a delay between retries of failed Subscription
    # @param restart_terminator [#call, nil] a callable object which, when called - accepts PgEventstore::Subscription
    #   object to determine whether restarts should be stopped(true - stops restarts, false - continues restarts)
    # @return [void]
    def subscribe(subscription_name, handler:, options: {}, middlewares: nil,
                  pull_interval: config.subscription_pull_interval,
                  max_retries: config.subscription_max_retries,
                  retries_interval: config.subscription_retries_interval,
                  restart_terminator: config.subscription_restart_terminator)
      subscription = Subscription.using_connection(config.name).new(
        set: @set_name, name: subscription_name, options: options, chunk_query_interval: pull_interval,
        max_restarts_number: max_retries, time_between_restarts: retries_interval
      )
      runner = SubscriptionRunner.new(
        stats: SubscriptionHandlerPerformance.new,
        events_processor: EventsProcessor.new(create_event_handler(middlewares, handler)),
        subscription: subscription,
        restart_terminator: restart_terminator
      )

      @subscription_feeder.add(runner)
      true
    end

    # @return [Array<PgEventstore::Subscription>]
    def subscriptions
      @subscription_feeder.read_only_subscriptions
    end

    # @return [PgEventstore::SubscriptionsSet, nil]
    def subscriptions_set
      @subscription_feeder.read_only_subscriptions_set
    end

    private

    # @param middlewares [Array<Symbol>, nil]
    # @param handler [#call]
    # @return [Proc]
    def create_event_handler(middlewares, handler)
      deserializer = EventDeserializer.new(select_middlewares(middlewares), config.event_class_resolver)
      ->(raw_event) { handler.call(deserializer.deserialize(raw_event)) }
    end

    # @param middlewares [Array, nil]
    # @return [Array<Object<#serialize, #deserialize>>]
    def select_middlewares(middlewares = nil)
      return config.middlewares.values unless middlewares

      config.middlewares.slice(*middlewares).values
    end
  end
end

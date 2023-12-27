# frozen_string_literal: true

require 'forwardable'
require 'securerandom'
require_relative 'subscription'
require_relative 'events_processor'
require_relative 'subscription_stats'
require_relative 'subscription_runner'
require_relative 'object_state'
require_relative 'subscriptions_set'
require_relative 'subscriptions_feeder'
require_relative 'subscription_runners'

module PgEventstore
  class SubscriptionsManager
    extend Forwardable

    attr_reader :config
    private :config

    def_delegators :@subscriptions_runner, :start_all, :stop_all

    # @param config [PgEventstore::Config]
    # @param set_name [String]
    def initialize(config, set_name)
      @config = config
      @set_name = set_name
      @subscriptions_runner = SubscriptionRunners.new(config.name, set_name)
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
    # @param refresh_interval [Integer] an interval in seconds to determine how often to query new events of the given
    #   subscription.
    # @param max_retries [Integer] max number of retries of failed subscription
    # @return [void]
    def subscribe(subscription_name, handler:, options: {}, middlewares: nil, refresh_interval: 5, max_retries: 100)
      subscription = Subscription.using_connection(config.name).init_by(
        set: @set_name, name: subscription_name, options: options, chunk_query_interval: refresh_interval,
        max_restarts_number: max_retries
      )

      runner = SubscriptionRunner.new(
        stats: SubscriptionStats.new,
        events_processor: EventsProcessor.new(handler(middlewares, handler)),
        subscription: subscription
      )

      @subscriptions_runner.add(runner)
    end

    private

    # @param middlewares [Array<Symbol>, nil]
    # @param handler [#call]
    # @return [Proc]
    def handler(middlewares, handler)
      deserializer = EventDeserializer.new(middlewares(middlewares), config.event_class_resolver)
      ->(raw_event) { handler.call(deserializer.deserialize(raw_event)) }
    end

    # @param middlewares [Array, nil]
    # @return [Array<Object<#serialize, #deserialize>>]
    def middlewares(middlewares = nil)
      return config.middlewares.values unless middlewares

      config.middlewares.slice(*middlewares).values
    end
  end
end
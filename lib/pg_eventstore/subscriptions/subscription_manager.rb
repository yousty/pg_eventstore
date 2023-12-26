# frozen_string_literal: true

require 'forwardable'
require 'securerandom'
require_relative 'subscription'
require_relative 'events_processor'
require_relative 'subscription_stats'
require_relative 'subscription_runner'
require_relative 'object_state'

module PgEventstore
  class SubscriptionManager
    attr_reader :config, :subscription_set
    private :config, :subscription_set

    # @param config [PgEventstore::Config]
    # @param subscription_set [String]
    def initialize(config, subscription_set)
      @config = config
      @subscription_set = subscription_set
      @runners = {}
      @lock_id = SecureRandom.uuid
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
    # @return [void]
    def subscribe(subscription_name, handler:, options: {}, middlewares: nil, refresh_interval: 5)
      subscription = Subscription.using_connection(config.name).init_by(
        set: subscription_set, name: subscription_name, options: options, chunk_query_interval: refresh_interval,
        lock_id: @lock_id
      )

      runner = SubscriptionRunner.new(
        stats: SubscriptionStats.new,
        events_processor: EventsProcessor.new(handler(middlewares, handler)),
        subscription: subscription
      )

      @runners[runner.id] = runner
    end

    # @return [void]
    def start_all
      lock_all
      @runners.each_value(&:start)
      @feeder ||= Thread.new do
        loop do
          sleep 1

          runners = @runners.values.select(&:running?).select(&:time_to_feed?)
          next if runners.empty?

          runners_query_options = runners.map { |runner| [runner.id, runner.next_chunk_query_opts] }
          raw_events = subscription_queries.subscriptions_events(runners_query_options)
          raw_events.group_by { |attrs| attrs['runner_id'] }.each do |runner_id, events|
            @runners[runner_id].feed(events)
          end
        end
      end
      nil
    end

    # @return [void]
    def stop_all
      @feeder&.exit
      @feeder = nil
      @runners.each_value(&:stop)
      @runners.each_value(&:wait_for_finish)
      unlock_all
      nil
    end

    private

    def lock_all
      @runners.each_value { |runner| runner.lock!(@lock_id) }
    end

    def unlock_all
      @runners.each_value(&:unlock!)
    end

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

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(config.name)
    end

    # @return [PgEventstore::SubscriptionQueries]
    def subscription_queries
      SubscriptionQueries.new(connection)
    end
  end
end

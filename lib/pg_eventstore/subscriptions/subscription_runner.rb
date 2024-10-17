# frozen_string_literal: true

require 'forwardable'

module PgEventstore
  # This class connects Subscription and EventsProcessor. Its public API is directed on locking/unlocking related
  # Subscription, starting/stopping/restarting EventsProcessor and calculating options(starting position, number of
  # events to fetch, etc) for the events pulling query.
  # @!visibility private
  class SubscriptionRunner
    extend Forwardable

    # @return [Integer]
    MAX_EVENTS_PER_CHUNK = 1_000
    # @return [Integer]
    MIN_EVENTS_PER_CHUNK = 10
    # @return [Integer]
    INITIAL_EVENTS_PER_CHUNK = 10

    # @!attribute subscription
    #   @return [PgEventstore::Subscription]
    attr_reader :subscription

    def_delegators :@events_processor, :start, :stop, :stop_async, :feed, :wait_for_finish, :restore, :state, :running?,
                   :clear_chunk, :within_state
    def_delegators :@subscription, :lock!, :id

    # @param stats [PgEventstore::SubscriptionHandlerPerformance]
    # @param events_processor [PgEventstore::EventsProcessor]
    # @param subscription [PgEventstore::Subscription]
    # @param restart_terminator [#call, nil]
    # @param failed_subscription_notifier [#call, nil]
    def initialize(stats:, events_processor:, subscription:, restart_terminator: nil,
                   failed_subscription_notifier: nil)
      @stats = stats
      @events_processor = events_processor
      @subscription = subscription
      @restart_terminator = restart_terminator
      @failed_subscription_notifier = failed_subscription_notifier

      attach_callbacks
    end

    # @return [Hash]
    def next_chunk_query_opts
      @subscription.options.merge(from_position: next_chunk_global_position, max_count: estimate_events_number)
    end

    # @return [Boolean]
    def time_to_feed?
      @subscription.last_chunk_fed_at + @subscription.chunk_query_interval <= Time.now.utc
    end

    private

    # @return [Integer]
    def next_chunk_global_position
      (
        @subscription.last_chunk_greatest_position || @subscription.current_position ||
          @subscription.options[:from_position] || 0
      ) + 1
    end

    # @return [Integer]
    def estimate_events_number
      return INITIAL_EVENTS_PER_CHUNK if @stats.average_event_processing_time.zero?

      events_per_chunk = (@subscription.chunk_query_interval / @stats.average_event_processing_time).round
      events_to_fetch = [events_per_chunk, MAX_EVENTS_PER_CHUNK].min - @events_processor.events_left_in_chunk
      return 0 if events_to_fetch < 0 # We still have a lot of events in the chunk - no need to fetch more

      [events_to_fetch, MIN_EVENTS_PER_CHUNK].max
    end

    # @return [void]
    def attach_callbacks
      @events_processor.define_callback(
        :process, :around,
        SubscriptionRunnerHandlers.setup_handler(:track_exec_time, @stats)
      )
      @events_processor.define_callback(
        :process, :after,
        SubscriptionRunnerHandlers.setup_handler(:update_subscription_stats, @subscription, @stats)
      )

      @events_processor.define_callback(
        :error, :after,
        SubscriptionRunnerHandlers.setup_handler(:update_subscription_error, @subscription)
      )
      @events_processor.define_callback(
        :error, :after,
        SubscriptionRunnerHandlers.setup_handler(
          :restart_events_processor,
          @subscription, @restart_terminator, @failed_subscription_notifier, @events_processor
        )
      )

      @events_processor.define_callback(
        :feed, :after,
        SubscriptionRunnerHandlers.setup_handler(:update_subscription_chunk_stats, @subscription)
      )

      @events_processor.define_callback(
        :restart, :after,
        SubscriptionRunnerHandlers.setup_handler(:update_subscription_restarts, @subscription)
      )

      @events_processor.define_callback(
        :change_state, :after,
        SubscriptionRunnerHandlers.setup_handler(:update_subscription_state, @subscription)
      )
    end
  end
end

# frozen_string_literal: true

require 'forwardable'

module PgEventstore
  # This class connects Subscription and EventsProcessor. Its public API is directed on locking/unlocking related
  # Subscription, starting/stopping/restarting EventsProcessor and calculating options(starting position, number of
  # events to fetch, etc) for the events pulling query.
  # @!visibility private
  class SubscriptionRunner
    extend Forwardable

    MAX_EVENTS_PER_CHUNK = 1_000
    MIN_EVENTS_PER_CHUNK = 10
    INITIAL_EVENTS_PER_CHUNK = 10

    attr_reader :subscription

    def_delegators :@events_processor, :start, :stop, :stop_async, :feed, :wait_for_finish, :restore, :state, :running?
    def_delegators :@subscription, :lock!, :id

    # @param stats [PgEventstore::SubscriptionHandlerPerformance]
    # @param events_processor [PgEventstore::EventsProcessor]
    # @param subscription [PgEventstore::Subscription]
    # @param restart_terminator [#call, nil]
    def initialize(stats:, events_processor:, subscription:, restart_terminator: nil)
      @stats = stats
      @events_processor = events_processor
      @subscription = subscription
      @restart_terminator = restart_terminator

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
      @events_processor.define_callback(:process, :around, method(:track_exec_time))
      @events_processor.define_callback(:process, :after, method(:update_subscription_stats))
      @events_processor.define_callback(:error, :after, method(:update_subscription_error))
      @events_processor.define_callback(:error, :after, method(:restart_subscription))
      @events_processor.define_callback(:feed, :after, method(:update_subscription_chunk_stats))
      @events_processor.define_callback(:restart, :after, method(:update_subscription_restarts))
      @events_processor.define_callback(:change_state, :after, method(:update_subscription_state))
    end

    # @param action [Proc]
    # @return [void]
    def track_exec_time(action, *)
      @stats.track_exec_time { action.call }
    end

    # @param current_position [Integer]
    # @return [void]
    def update_subscription_stats(current_position)
      @subscription.update(
        average_event_processing_time: @stats.average_event_processing_time,
        current_position: current_position,
        total_processed_events: @subscription.total_processed_events + 1
      )
    end

    # @param state [String]
    # @return [void]
    def update_subscription_state(state)
      @subscription.update(state: state)
    end

    # @return [void]
    def update_subscription_restarts
      @subscription.update(last_restarted_at: Time.now.utc, restart_count: @subscription.restart_count + 1)
    end

    # @param error [StandardError]
    # @return [void]
    def update_subscription_error(error)
      @subscription.update(last_error: Utils.error_info(error), last_error_occurred_at: Time.now.utc)
    end

    # @param global_position [Integer]
    # @return [void]
    def update_subscription_chunk_stats(global_position)
      @subscription.update(last_chunk_fed_at: Time.now.utc, last_chunk_greatest_position: global_position)
    end

    # @param _error [StandardError]
    # @return [void]
    def restart_subscription(_error)
      return if @restart_terminator&.call(@subscription.dup)
      return if @subscription.restart_count >= @subscription.max_restarts_number

      Thread.new do
        sleep @subscription.time_between_restarts
        restore
      end
    end
  end
end

# frozen_string_literal: true

require 'forwardable'

module PgEventstore
  # @!visibility private
  class SubscriptionRunner
    extend Forwardable

    MAX_EVENTS_PER_CHUNK = 1_000
    INITIAL_EVENTS_PER_CHUNK = 10

    def_delegators :@events_processor, :start, :stop, :feed, :wait_for_finish
    def_delegators :@subscription, :lock!, :unlock!, :id, :persist

    # @param stats [PgEventstore::SubscriptionStats]
    # @param events_processor [PgEventstore::EventsProcessor]
    # @param subscription [PgEventstore::Subscription]
    def initialize(stats:, events_processor:, subscription:)
      @stats = stats
      @events_processor = events_processor
      @subscription = subscription

      attach_callbacks
    end

    # @return [Hash]
    def next_chunk_query_opts
      @subscription.options.merge(from_position: next_chunk_global_position, max_count: estimate_events_number)
    end

    # @return [Boolean]
    def running?
      @events_processor.state.running?
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
      return INITIAL_EVENTS_PER_CHUNK if @stats.events_processing_frequency.zero?

      estimate_number =
        @subscription.chunk_query_interval / @stats.events_processing_frequency - @events_processor.events_left_in_chunk
      [estimate_number.round, MAX_EVENTS_PER_CHUNK].min
    end

    # @return [void]
    def attach_callbacks
      @events_processor.define_callback(:process, :around, method(:track_exec_time))
      @events_processor.define_callback(:process, :after, method(:update_subscription_stats))
      @events_processor.define_callback(:error, :after, method(:update_subscription_error))
      @events_processor.define_callback(:feed, :after, method(:update_subscription_chunk_stats))
      @events_processor.state.define_callback(:change_state, :after, method(:update_subscription_state))
      @events_processor.state.define_callback(:restart, :after, method(:update_subscription_restarts))
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
        events_processing_frequency: @stats.events_processing_frequency,
        current_position: current_position,
        events_processed_total: @subscription.events_processed_total + 1
      )
    end

    # @return [void]
    def update_subscription_state
      @subscription.update(state: @events_processor.state.to_s)
    end

    # @return [void]
    def update_subscription_restarts
      @subscription.update(last_restarted_at: Time.now.utc, restarts_count: @subscription.restarts_count + 1)
    end

    # @param error [StandardError]
    # @return [void]
    def update_subscription_error(error)
      @subscription.update(last_error: Utils.error_info(error), last_error_occurred_at: Time.now.utc)
    end

    # @param global_position [Integer, nil]
    # @return [void]
    def update_subscription_chunk_stats(global_position)
      global_position ||= @subscription.last_chunk_greatest_position
      @subscription.update(last_chunk_fed_at: Time.now.utc, last_chunk_greatest_position: global_position)
    end
  end
end

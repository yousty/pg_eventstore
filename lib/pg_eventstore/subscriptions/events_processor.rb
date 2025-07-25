# frozen_string_literal: true

module PgEventstore
  # This class actually processes events.
  # @!visibility private
  class EventsProcessor
    include Extensions::CallbacksExtension
    extend Forwardable

    def_delegators :@basic_runner, :state, :start, :stop, :wait_for_finish, :stop_async, :restore, :running?,
                   :within_state

    # @param handler [#call]
    # @param graceful_shutdown_timeout [Integer, Float] seconds. Determines how long to wait before force-shutdown
    #   the runner when stopping it using #stop_async
    # @param recovery_strategies [Array<PgEventstore::RunnerRecoveryStrategy>]
    def initialize(handler, graceful_shutdown_timeout:, recovery_strategies: [])
      @handler = handler
      @raw_events = []
      @basic_runner = BasicRunner.new(
        run_interval: 0,
        async_shutdown_time: graceful_shutdown_timeout,
        recovery_strategies: recovery_strategies
      )
      attach_runner_callbacks
    end

    # @param raw_events [Array<Hash>]
    # @return [void]
    def feed(raw_events)
      raise EmptyChunkFedError.new("Empty chunk was fed!") if raw_events.empty?

      within_state(:running) do
        callbacks.run_callbacks(:feed, Utils.original_global_position(raw_events.last))
        @raw_events.push(*raw_events)
      end
    end

    # Number of unprocessed events which are currently in a queue
    # @return [Integer]
    def events_left_in_chunk
      @raw_events.size
    end

    # @return [void]
    def clear_chunk
      @raw_events.clear
    end

    private

    def attach_runner_callbacks
      @basic_runner.define_callback(
        :process_async, :before,
        EventsProcessorHandlers.setup_handler(:process_event, @callbacks, @handler, @raw_events)
      )

      @basic_runner.define_callback(
        :after_runner_died, :before, EventsProcessorHandlers.setup_handler(:after_runner_died, callbacks)
      )

      @basic_runner.define_callback(
        :before_runner_restored, :before, EventsProcessorHandlers.setup_handler(:before_runner_restored, callbacks)
      )

      @basic_runner.define_callback(
        :change_state, :before, EventsProcessorHandlers.setup_handler(:change_state, callbacks)
      )
    end
  end
end

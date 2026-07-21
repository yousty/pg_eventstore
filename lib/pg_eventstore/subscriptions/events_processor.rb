# frozen_string_literal: true

module PgEventstore
  # This class actually processes events.
  # @!visibility private
  class EventsProcessor
    include Extensions::CallbacksExtension
    extend Forwardable

    def_delegators :@basic_runner, :state, :start, :stop, :wait_for_finish, :stop_async, :restore, :running?,
                   :within_state

    # @param graceful_shutdown_timeout [Integer, Float] seconds. Determines how long to wait before force-shutdown
    #   the runner when stopping it using #stop_async
    # @param consumer [PgEventstore::EventsProcessorConsumer]
    # @param events_repository [PgEventstore::Chunks::Repository]
    # @param recovery_strategies [Array<PgEventstore::RunnerRecoveryStrategy>]
    def initialize(graceful_shutdown_timeout:, consumer:, events_repository: Chunks::Repository.new,
                   recovery_strategies: [])
      @consumer = consumer
      @events_repository = events_repository
      @repository_cond = @events_repository.new_cond
      @basic_runner = BasicRunner.new(
        run_interval: 0,
        async_shutdown_time: graceful_shutdown_timeout,
        recovery_strategies:
      )
      attach_runner_callbacks
    end

    # @param chunk [PgEventstore::Chunks::Chunk]
    # @return [void]
    def feed(chunk)
      raise EmptyChunkFedError.new('Empty chunk was fed!') if chunk.drained?

      within_state(:running) do
        callbacks.run_callbacks(:feed, chunk.last.subscription_position)
        @events_repository.add_chunk(chunk, condition: @repository_cond)
      end
    end

    # Number of unprocessed events which are currently in a queue
    # @return [Integer]
    def events_left_in_repo
      @events_repository.size
    end

    # @return [void]
    def clear_events_repository
      @events_repository.clear
      @consumer.clear_unprocessed_events
    end

    private

    def attach_runner_callbacks
      @basic_runner.define_callback(
        :process_async, :before,
        EventsProcessorHandlers.setup_handler(
          :consume_events, @consumer, @callbacks, @events_repository, @repository_cond
        )
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

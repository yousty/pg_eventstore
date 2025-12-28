# frozen_string_literal: true

module PgEventstore
  # Implements simple background job runner. A job execution is done via declaring a callback on a specific action. The
  # implementation also allows you to hook into different places of life cycle of the runner by defining callbacks on
  # various actions. Here is the list of available actions:
  # - :before_runner_started. Happens before the runner's state switches from "initial"/"stopped" to "running" and
  #   runner's thread is started. It is also fired when the runner is restoring - right after :before_runner_restored
  #   action.
  # - :after_runner_stopped. Happens after runner's state got switched from "running"/"dead" to "stopped" and runner's
  #   thread is terminated.
  # - :before_runner_restored. Happens before runner's state gets switched from "dead" to "running" and runner's
  #   thread is started.
  # - :process_async. Happens each @run_interval seconds within runner's thread.
  # - :after_runner_died. Happens when runner's state switches to "dead" because of exception inside runner's thread.
  #   Callback function must be able to accept one argument - the exception which caused the runner to die will be
  #   passed.
  # - :change_state. It happens each time the runner changes the state. Callback function must be able to accept one
  #   argument - current state will be passed.
  #
  # Example of BasicRunner usage:
  #   class MyAwesomeRunner
  #     extend Forwardable
  #
  #     def_delegators :@basic_runner, :start, :stop, :wait_for_finish, :stop_async, :restore
  #
  #     class SimpleRecoveryStrategy
  #       include PgEventstore::RunnerRecoveryStrategy
  #
  #       def initialize(restore_func)
  #         @attempts_count = 0
  #         @restore_func = restore_func
  #       end
  #
  #       def recovers?(error)
  #         error.message.include?("I can not handle this any more!")
  #       end
  #
  #       def recover(error)
  #         (@attempts_count < 3).tap do |res|
  #           @attempts_count += 1
  #           @restore_func.call if res
  #         end
  #       end
  #     end
  #
  #     def initialize
  #       @basic_runner = PgEventstore::BasicRunner.new(
  #         run_interval: 1, async_shutdown_time: 2, recovery_strategies: recovery_strategies
  #       )
  #       @jobs_performed = 0
  #       @jobs_limit = 3
  #       attach_runner_callbacks
  #     end
  #
  #     protected
  #
  #     def work_harder
  #       @jobs_limit += 3
  #     end
  #
  #     private
  #
  #     def attach_runner_callbacks
  #       @basic_runner.define_callback(:change_state, :after, method(:state_changed))
  #       @basic_runner.define_callback(:process_async, :before, method(:process_action))
  #       @basic_runner.define_callback(:process_async, :after, method(:count_jobs))
  #       @basic_runner.define_callback(:before_runner_started, :before, method(:before_runner_started))
  #       @basic_runner.define_callback(:after_runner_stopped, :before, method(:after_runner_stopped))
  #       @basic_runner.define_callback(:after_runner_died, :before, method(:after_runner_died))
  #     end
  #
  #     def process_action
  #       raise "What's the point? I can not handle this any more!" if @jobs_performed >= @jobs_limit
  #       puts "Doing some heavy lifting job"
  #       sleep 2 # Simulate long running job
  #     end
  #
  #     def count_jobs
  #       @jobs_performed += 1
  #     end
  #
  #     # @param state [String]
  #     def state_changed(state)
  #       puts "New state is #{state.inspect}"
  #     end
  #
  #     def before_runner_started
  #       puts "Doing some preparations..."
  #     end
  #
  #     def after_runner_stopped
  #       puts "You job is not processing any more. Total jobs performed: #{@jobs_performed}. Bye-bye!"
  #     end
  #
  #     def after_runner_died(error)
  #       puts "Error occurred: #{error.inspect}"
  #     end
  #
  #     def recovery_strategies
  #       [SimpleRecoveryStrategy.new(method(:work_harder))]
  #     end
  #   end
  #
  #   runner = MyAwesomeRunner.new
  #   runner.start # to start your background runner to process the job, defined by #process_action method
  #   runner.stop # to stop the runner
  #
  # See {PgEventstore::RunnerState} for the list of available states
  # See {PgEventstore::CallbacksExtension} and {PgEventstore::Callbacks} for more info about how to use callbacks
  class BasicRunner
    extend Forwardable
    include Extensions::CallbacksExtension

    def_delegators :@state, :initial?, :running?, :halting?, :stopped?, :dead?

    # @param run_interval [Integer, Float] seconds. Determines how often to run async task. Async task is determined by
    #   :after_runner_stopped callback
    # @param async_shutdown_time [Integer, Float] seconds. Determines how long to wait before force-shutdown the runner.
    #   It is only meaningful for the #stop_async
    def initialize(run_interval:, async_shutdown_time:, recovery_strategies: [])
      @run_interval = run_interval
      @async_shutdown_time = async_shutdown_time
      @recovery_strategies = recovery_strategies
      @state = RunnerState.new
      @mutex = Thread::Mutex.new
      @runner = nil
      delegate_change_state_cbx
    end

    # Start asynchronous runner. If the runner is dead - please use #restore to restart it.
    # @return [self]
    def start
      synchronize do
        return self unless @state.initial? || @state.stopped?

        callbacks.run_callbacks(:before_runner_started)
        _start
      end
      self
    end

    # Stop asynchronous runner. This operation is immediate and it won't be waiting for current job to finish - it will
    # instantly halt it. If you care about the result of your async job - use #stop_async instead.
    # @return [self]
    def stop
      synchronize do
        return self unless @state.running? || @state.dead?

        @runner&.exit
        @runner = nil
        @state.stopped!
        callbacks.run_callbacks(:after_runner_stopped)
      end
      self
    end

    # Asynchronously stop asynchronous runner. This operation spawns another thread to gracefully stop the runner. It
    # will wait up to @async_shutdown_time seconds before force-stopping the runner.
    # @return [self]
    def stop_async
      synchronize do
        return self unless @state.running? || @state.dead?

        begin
          @state.halting!
        ensure
          Thread.new do
            stopping_at = Time.now.utc
            halt = false
            loop do
              synchronize do
                # Give the runner up to @async_shutdown_time seconds for graceful shutdown
                @runner&.exit if Time.now.utc - stopping_at > @async_shutdown_time

                unless @runner&.alive?
                  @state.stopped!
                  callbacks.run_callbacks(:after_runner_stopped)
                end
              ensure
                next if @runner&.alive?

                @runner = nil
                halt = true
              end
              break if halt

              sleep 0.1
            end
          end
        end
      end
      self
    end

    # Restores the runner after its death.
    # @return [self]
    def restore
      within_state(:dead) do
        callbacks.run_callbacks(:before_runner_restored)
        _start
      end
      self
    end

    # Wait until the runner switches the state to either "stopped" or "dead". This operation is synchronous.
    # @return [self]
    def wait_for_finish
      loop do
        continue = synchronize do
          @state.halting? || @state.running?
        end
        break unless continue

        sleep 0.1
      end
      self
    end

    # @return [String]
    def state
      @state.to_s
    end

    # @param state [Symbol]
    # @return [Object, nil] a result of evaluating of passed block
    def within_state(state, &)
      synchronize do
        return unless @state.public_send("#{RunnerState::STATES.fetch(state)}?")

        yield
      end
    end

    protected

    # @param error [StandardError]
    # @param strategy [PgEventstore::RunnerRecoveryStrategy]
    # @param current_runner_id [Integer]
    # @return [Thread]
    def async_recover(error, strategy, current_runner_id)
      Thread.new do
        init_recovery_ripper(current_runner_id)
        Thread.current.exit unless strategy.recover(error)
        recoverable { restore }
      end
    end

    private

    def synchronize(&)
      @mutex.synchronize(&)
    end

    # @return [void]
    def _start
      @state.running!
    ensure
      @runner = Thread.new do
        recoverable do
          loop do
            Thread.current.exit unless @state.running?
            sleep @run_interval

            callbacks.run_callbacks(:process_async)
          end
        end
      end
    end

    # Delegates :change_state action to the runner
    # @return [void]
    def delegate_change_state_cbx
      @state.define_callback(:change_state, :before, method(:change_state))
    end

    # @return [void]
    def change_state(...)
      callbacks.run_callbacks(:change_state, ...)
    end

    # @param error [StandardError]
    # @return [PgEventstore::RunnerRecoveryStrategy, nil]
    def suitable_strategy(error)
      @recovery_strategies.find { _1.recovers?(error) }
    end

    # @return [void]
    def recoverable
      yield
    rescue => error
      synchronize do
        raise unless @state.halting? || @state.running?

        recovery_strategy = suitable_strategy(error)
        @state.dead!
        callbacks.run_callbacks(:after_runner_died, error)
      ensure
        async_recover(error, recovery_strategy, @runner.__id__) if recovery_strategy
      end
    end

    # @param current_runner_id [Integer]
    # @return [Thread]
    def init_recovery_ripper(current_runner_id)
      recovery_job = Thread.current
      Thread.new do
        loop do
          synchronize do
            recovery_job.exit unless @state.dead?
            recovery_job.exit unless current_runner_id == @runner.__id__
          end
          break unless recovery_job.alive?

          sleep 1
        end
      end
    end
  end
end

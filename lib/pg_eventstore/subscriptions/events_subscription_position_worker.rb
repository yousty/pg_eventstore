# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventsSubscriptionPositionWorker
    extend Forwardable

    attr_reader :config_name

    def_delegators :@basic_runner, :start, :stop, :state, :stop_async, :wait_for_finish

    class ReindexTime
      include Extensions::OptionsExtension
      include Extensions::OptionsDefaults

      option(:time)
    end

    # @param config_name [Symbol]
    def initialize(config_name)
      @config_name = config_name
      @basic_runner = BasicRunner.new(
        run_interval: 0,
        async_shutdown_time: 5,
        recovery_strategies: [RunnerRecoveryStrategies::RestoreConnection.new(config_name)]
      )
      @next_reindex_at = ReindexTime.new
      attach_runner_callbacks
    end

    private

    # @return [void]
    def attach_runner_callbacks
      @basic_runner.define_callback(
        :process_async, :before,
        EventsSubscriptionPositionWorkerHandlers.setup_handler(
          :assign_subscription_position,
          event_subscription_position_queries,
          config.events_subscription_position_update_interval
        )
      )
      @basic_runner.define_callback(
        :process_async, :before,
        EventsSubscriptionPositionWorkerHandlers.setup_handler(
          :reindex,
          event_subscription_position_queries,
          @next_reindex_at
        )
      )
    end

    # @return [PgEventstore::EventSubscriptionPositionQueries]
    def event_subscription_position_queries
      EventSubscriptionPositionQueries.new(connection)
    end

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(config_name)
    end

    # @return [PgEventstore::Config]
    def config
      PgEventstore.config(config_name)
    end
  end
end

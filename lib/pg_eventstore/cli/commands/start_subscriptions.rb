# frozen_string_literal: true

require_relative 'callback_handlers/start_cmd_handlers'

module PgEventstore
  module CLI
    module Commands
      class StartSubscriptions < BaseCommand
        KEEP_ALIVE_INTERVAL = 5 # seconds

        def initialize(...)
          super
          @subscription_managers = Set.new
          attach_callbacks
        end

        # @return [void]
        def call
          super
          validate_subscriptions
          setup_killsig
          persist_pid
          keep_process_alive
        end

        private

        # @return [void]
        def validate_subscriptions
          return if @subscription_managers.any?(&:running?)

          PgEventstore.logger&.warn("No subscriptions start ups were detected. Existing...")
          Kernel.exit(1)
        end

        # @return [void]
        def setup_killsig
          Kernel.trap('TERM') do
            Thread.new do
              PgEventstore.logger&.info("Received TERM signal, stopping subscriptions and exiting...")
            end.join
            # Because the implementation uses Mutex - wrap it into Thread to bypass the limitations of Kernel#trap
            @subscription_managers.map do |manager|
              Thread.new do
                # Initiate graceful shutdown
                manager.stop
              end
            end.each(&:join)
            Utils.remove_file(options.pid_path)
            Kernel.exit(0)
          end
        end

        # @return [void]
        def persist_pid
          Utils.write_to_file(options.pid_path, Process.pid.to_s)
        end

        # @return [void]
        def keep_process_alive
          loop do
            # SubscriptionsManager#subscriptions_set becomes nil when everything gets stopped.
            if @subscription_managers.all? { |manager| manager.subscriptions_set.nil? }
              PgEventstore.logger&.info("All subscriptions were gracefully shut down. Exiting now...")
              Kernel.exit(0)
            end
            sleep KEEP_ALIVE_INTERVAL
          end
        end

        # @return [void]
        def attach_callbacks
          PgEventstore::SubscriptionsManager.callbacks.define_callback(
            :start, :before,
            CallbackHandlers::StartCmdHandlers.setup_handler(:register_managers, @subscription_managers)
          )
          PgEventstore::SubscriptionsManager.callbacks.define_callback(
            :start, :around,
            CallbackHandlers::StartCmdHandlers.setup_handler(:handle_start_up)
          )
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative 'callback_handlers/start_cmd_handlers'

module PgEventstore
  module CLI
    module Commands
      # @!visibility private
      class StartSubscriptionsCommand < BaseCommand
        # @return [Integer] seconds
        KEEP_ALIVE_INTERVAL = 2

        def initialize(...)
          super
          @subscription_managers = Set.new
          @running = false
          attach_callbacks
        end

        # @return [Integer] exit code
        def call
          return ExitCodes::ERROR unless running_subscriptions?

          @running = true
          setup_killsig
          persist_pid
          keep_process_alive
          ExitCodes::SUCCESS
        rescue SubscriptionAlreadyLockedError => error
          PgEventstore.logger&.error(
            "SubscriptionsSet##{error.lock_id} is still there. Are you stopping it at all?"
          )
          ExitCodes::ERROR
        end

        private

        # @return [Boolean]
        def running_subscriptions?
          return true if @subscription_managers.any?(&:running?)

          PgEventstore.logger&.warn("No subscriptions start ups were detected. Existing...")
          false
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
          ensure
            @running = false
            Utils.remove_file(options.pid_path)
          end
        end

        # @return [void]
        def persist_pid
          Utils.write_to_file(options.pid_path, Process.pid.to_s)
        end

        # @return [void]
        def keep_process_alive
          PgEventstore.logger&.info("Startup is successful. Processing subscriptions...")
          loop do
            # SubscriptionsManager#subscriptions_set becomes nil when everything gets stopped.
            if @subscription_managers.all? { |manager| manager.subscriptions_set.nil? }
              PgEventstore.logger&.info("All subscriptions were gracefully shut down. Exiting now...")
              break
            end
            break unless @running
            sleep KEEP_ALIVE_INTERVAL
          end
        end

        # @return [void]
        def attach_callbacks
          CLI.callbacks.define_callback(
            :start_manager, :before,
            CallbackHandlers::StartCmdHandlers.setup_handler(:register_managers, @subscription_managers)
          )
          CLI.callbacks.define_callback(
            :start_manager, :around,
            CallbackHandlers::StartCmdHandlers.setup_handler(:handle_start_up)
          )
        end
      end
    end
  end
end

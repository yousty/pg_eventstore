# frozen_string_literal: true

module PgEventstore
  module CLI
    module Commands
      class StopSubscriptionsCommand < BaseCommand
        # @return [Integer] exit code
        def call
          pid = Utils.read_pid(options.pid_path)&.to_i
          if pid && pid > 0
            PgEventstore.logger&.info("Stopping process #{pid}.")
            Process.kill('TERM', pid)
            return ExitCodes::SUCCESS
          end

          PgEventstore.logger&.error("Pid file #{options.pid_path.inspect} does not exist or empty.")
          ExitCodes::ERROR
        end
      end
    end
  end
end

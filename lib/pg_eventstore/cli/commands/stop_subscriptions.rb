# frozen_string_literal: true

module PgEventstore
  module CLI
    module Commands
      class StopSubscriptions < BaseCommand
        # @return [void]
        def call
          super
          pid = Utils.read_pid(options.pid_path)&.to_i
          if pid && pid > 0
            PgEventstore.logger&.info("Stopping process #{pid}.")
            Process.kill('TERM', pid)
            Kernel.exit(0)
          end

          PgEventstore.logger&.warn("Pid file #{options.pid_path.inspect} does not exist or empty.")
          Kernel.exit(1)
        end
      end
    end
  end
end

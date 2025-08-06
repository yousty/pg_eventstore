# frozen_string_literal: true

require 'tempfile'

class ConnectionHelper
  class << self
    # @param connection [PgEventstore::Connection]
    def test_forking(connection)
      connection.with { |c| c.exec('select version()') } # warm up
      pids = 2.times.map do
        fork do
          captured_stderr = Tempfile.new('err')
          $stderr.reopen(captured_stderr)

          begin
            connection.with do |c|
              c.transaction do
                sleep 0.2
                5.times { c.exec('select version()'); sleep 0.02 }
              end
            end

            REDIS.set("process-#{Process.pid}", 'OK')
          rescue => e
            REDIS.set("process-#{Process.pid}", e.inspect)
          ensure
            REDIS.set("process-err-#{Process.pid}", captured_stderr.tap(&:rewind).read)
          end

          exit! # prevent at_exit hooks from running
        end
      end
      sleep 2
      Process.kill('TERM', *pids)

      pids.map do |pid|
        { status: REDIS.get("process-#{pid}"), errors: REDIS.get("process-err-#{pid}") }
      end
    end
  end
end

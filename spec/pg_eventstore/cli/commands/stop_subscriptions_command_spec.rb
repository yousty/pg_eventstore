# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::Commands::StopSubscriptionsCommand do
  let(:instance) { described_class.new(options) }
  let(:options) { PgEventstore::CLI::ParserOptions::SubscriptionOptions.new }

  describe '#call' do
    subject { instance.call }

    let(:another_process_pid) do
      Process.spawn('ruby', '-e', 'Kernel.trap("TERM") { exit }; sleep 2').tap do
        Process.detach(_1)
      end
    end

    before do
      PgEventstore::Utils.write_to_file(options.pid_path, another_process_pid.to_s)
    end

    after do
      PgEventstore::Utils.remove_file(options.pid_path)
    end

    it 'stops the process by the given pid file path' do
      expect { subject; sleep 0.2 }.to change {
        begin
          Process.getpgid(another_process_pid)
        rescue Errno::ESRCH # No such process error
        end
      }.from(instance_of(Integer)).to(nil)
    end
  end
end

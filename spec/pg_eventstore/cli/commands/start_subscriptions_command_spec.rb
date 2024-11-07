# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::Commands::StartSubscriptionsCommand do
  let(:instance) { described_class.new(options) }
  let(:options) { PgEventstore::CLI::ParserOptions::SubscriptionOptions.new }

  describe '#call' do
    subject { subject_thread }

    let(:subject_thread) { Thread.new { Thread.current[:result] = instance.call } }

    after do
      subject_thread.exit
      PgEventstore::Utils.remove_file(options.pid_path)
    end

    context 'when there are no running subscriptions' do
      before do
        options.requires = [CLIHelper.non_running_subscriptions_file_path]
        CLIHelper.persist_non_running_subscriptions_file
      end

      it 'does not keep process alive' do
        subject
        sleep 0.2
        expect(subject_thread).not_to be_alive
      end
      it 'returns error status code' do
        subject
        sleep 0.2
        expect(subject_thread[:result]).to eq(PgEventstore::CLI::ExitCodes::ERROR)
      end
      it 'does not persist process pid' do
        expect { subject; sleep 0.2 }.not_to change { PgEventstore::Utils.read_pid(options.pid_path) }
      end
    end

    context 'when there are running subscriptions' do
      before do
        options.requires = [CLIHelper.running_subscriptions_file_path]
        CLIHelper.persist_running_subscriptions_file
      end

      it 'keeps process alive' do
        subject
        sleep 0.2
        expect(subject_thread).to be_alive
      end
      it 'persists process pid' do
        expect { subject; sleep 0.2 }.to change { PgEventstore::Utils.read_pid(options.pid_path)&.to_i }.to(Process.pid)
      end

      context 'when running subscriptions get stopped' do
        before do
          stub_const("#{described_class}::KEEP_ALIVE_INTERVAL", 0.5)
        end

        it 'returns success status code and shuts down' do
          subject
          sleep 0.2
          CLIHelper.current_subscription_manager.stop
          sleep described_class::KEEP_ALIVE_INTERVAL
          aggregate_failures do
            expect(subject_thread[:result]).to eq(PgEventstore::CLI::ExitCodes::SUCCESS)
            expect(subject_thread).not_to be_alive
          end
        end
      end
    end
  end
end

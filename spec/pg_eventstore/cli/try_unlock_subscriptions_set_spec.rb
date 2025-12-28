# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::TryUnlockSubscriptionsSet do
  describe '.try_unlock' do
    subject { described_class.try_unlock(config_name, subscriptions_set_id) }

    let(:config_name) { :default }
    let(:subscriptions_set_id) { 123 }

    describe 'when unlocking is successful' do
      it { is_expected.to eq(true) }
    end

    describe 'when unlocking is not successful' do
      let(:subscriptions_set_id) { SubscriptionsSetHelper.create.id }

      before do
        stub_const('PgEventstore::CommandsHandler::RESTART_DELAY', 0)
        stub_const('PgEventstore::CommandsHandler::PULL_INTERVAL', 0)
        PgEventstore.configure do |c|
          c.subscription_graceful_shutdown_timeout = 0
        end
      end

      around do |example|
        # TryToDeleteSubscription creates "Ping" command to try to determine whether related SubscriptionsSet is alive.
        # If we delete it - it would mean it is alive, thus producing falsey result.
        thread = Thread.new do
          sleep 0.2
          queries = PgEventstore::SubscriptionsSetCommandQueries.new(PgEventstore.connection)
          cmd = queries.find_by(subscriptions_set_id:, command_name: 'Ping')
          queries.delete(cmd.id)
        end
        example.run
        thread.exit
      end

      it { is_expected.to eq(false) }
    end
  end
end

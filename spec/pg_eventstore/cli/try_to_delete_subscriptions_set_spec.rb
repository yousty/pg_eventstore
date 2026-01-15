# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::TryToDeleteSubscriptionsSet do
  let(:instance) { described_class.new(config_name, subscriptions_set_id) }
  let(:config_name) { :default }
  let(:subscriptions_set_id) { 123 }

  describe '#try_to_delete' do
    subject { instance.try_to_delete }

    context 'when SubscriptionsSet with the given id does not exist' do
      it { is_expected.to eq(true) }
    end

    context 'when SubscriptionsSet with the given id exists' do
      let!(:subscriptions_set) { SubscriptionsSetHelper.create(id: subscriptions_set_id) }

      before do
        stub_const('PgEventstore::CommandsHandler::RESTART_DELAY', 0)
        stub_const('PgEventstore::CommandsHandler::PULL_INTERVAL', 0)
      end

      context 'when SubscriptionsSet is alive' do
        around do |example|
          # TryToDeleteSubscription creates "Ping" command to try to determine whether related SubscriptionsSet is
          # alive. If we delete it - it would mean it is alive, thus producing falsey result.
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

      context 'when SubscriptionsSet is dead' do
        it { is_expected.to eq(true) }
      end
    end
  end
end

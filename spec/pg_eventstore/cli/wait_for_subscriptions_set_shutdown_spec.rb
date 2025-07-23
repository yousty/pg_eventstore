# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::WaitForSubscriptionsSetShutdown do
  let(:instance) { described_class.new(config_name, subscriptions_set_id) }
  let(:config_name) { :default }
  let(:subscriptions_set_id) { 123 }

  describe '#wait_for_shutdown' do
    subject { instance.wait_for_shutdown }

    context 'when SubscriptionsSet exist' do
      let!(:subscriptions_set) { SubscriptionsSetHelper.create(id: subscriptions_set_id) }

      before do
        PgEventstore.configure do |c|
          c.subscription_graceful_shutdown_timeout = 0
        end
      end

      after do
        PgEventstore.send(:init_variables)
      end

      it { is_expected.to eq(false) }
    end

    context 'when SubscriptionsSet gets deleted after certain amount of time' do
      let!(:subscriptions_set) { SubscriptionsSetHelper.create(id: subscriptions_set_id) }

      before do
        PgEventstore.configure do |c|
          c.subscription_graceful_shutdown_timeout = 5
        end
        stub_const("#{described_class}::SHUTDOWN_CHECK_INTERVAL", 1)
      end

      after do
        PgEventstore.send(:init_variables)
      end

      around do |example|
        thread = Thread.new do
          sleep described_class::SHUTDOWN_CHECK_INTERVAL + 0.2
          queries = PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection)
          queries.delete(subscriptions_set_id)
        end
        example.run
        thread.exit
      end

      it { is_expected.to eq(true) }
    end

    context 'when SubscriptionsSet does not exist' do
      it { is_expected.to eq(true) }
    end
  end
end

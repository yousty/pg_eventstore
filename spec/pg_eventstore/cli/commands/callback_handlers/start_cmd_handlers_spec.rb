# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::Commands::CallbackHandlers::StartCmdHandlers do
  it { is_expected.to be_a(PgEventstore::Extensions::CallbackHandlersExtension) }

  describe '.register_managers' do
    subject { described_class.register_managers(subscription_managers, manager) }

    let(:subscription_managers) { Set.new }
    let(:manager) { PgEventstore::SubscriptionsManager.new(config: PgEventstore.config, set_name: 'FooSet') }

    it 'adds the given manager to the list' do
      expect { subject }.to change { subscription_managers.to_a }.to([manager])
    end
  end

  describe '.handle_start_up' do
    subject { described_class.handle_start_up(action, manager) }

    let(:manager) { PgEventstore::SubscriptionsManager.new(config: PgEventstore.config, set_name: 'FooSet') }
    let(:action) { proc { manager.start! } }

    after do
      manager.stop
    end

    context 'when all is ok' do
      it 'starts subscriptions' do
        expect { subject }.to change { manager.running? }.to(true)
      end
    end

    context 'when SubscriptionAlreadyLockedError error is raised' do
      let(:existing_subscriptions_set) { SubscriptionsSetHelper.create(name: 'FooSub') }
      let!(:existing_locked_subscription) do
        SubscriptionsHelper.create_with_connection(
          set: 'FooSet', name: 'FooSub', locked_by: existing_subscriptions_set.id
        )
      end

      before do
        manager.subscribe('FooSub', handler: proc {})
        stub_const('PgEventstore::CLI::WaitForSubscriptionsSetShutdown::SHUTDOWN_CHECK_INTERVAL', 0.1)
        stub_const('PgEventstore::CommandsHandler::RESTART_DELAY', 0)
        stub_const('PgEventstore::CommandsHandler::PULL_INTERVAL', 0)
      end

      it 're-locks locked subscription' do
        expect { subject }.to change {
          existing_locked_subscription.reload.locked_by
        }.from(existing_subscriptions_set.id).to(kind_of(Integer))
      end
      it 'starts subscriptions' do
        expect { subject }.to change { manager.running? }.to(true)
      end
    end
  end
end

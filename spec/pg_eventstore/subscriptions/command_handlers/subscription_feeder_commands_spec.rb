# frozen_string_literal: true

RSpec.describe PgEventstore::CommandHandlers::SubscriptionFeederCommands do
  let(:instance) { described_class.new(config_name, subscription_feeder) }
  let(:config_name) { :default }
  let(:subscription_feeder) do
    PgEventstore::SubscriptionFeeder.new(
      config_name: config_name,
      subscriptions_set_lifecycle: subscriptions_set_lifecycle,
      subscriptions_lifecycle: subscriptions_lifecycle
    )
  end
  let(:subscriptions_set_lifecycle) do
    PgEventstore::SubscriptionsSetLifecycle.new(
      config_name,
      { name: 'MySubscriptionsSet', max_restarts_number: 0, time_between_restarts: 0 }
    )
  end
  let(:subscriptions_lifecycle) do
    PgEventstore::SubscriptionsLifecycle.new(config_name, subscriptions_set_lifecycle)
  end
  let(:subscriptions_set_id) { subscriptions_set_lifecycle.persisted_subscriptions_set.id }

  describe '#process' do
    subject { instance.process }

    let(:command_queries) { PgEventstore::SubscriptionsSetCommandQueries.new(PgEventstore.connection) }

    context 'when there are no commands' do
      it 'does nothing' do
        expect { subject }.not_to raise_error
      end
    end

    context 'when there is a "StopAll" command' do
      let!(:command) do
        command_queries.create(subscriptions_set_id: subscriptions_set_id, command_name: "StopAll", data: {})
      end

      before do
        allow(subscription_feeder).to receive(:stop_all).and_call_original
      end

      it 'stops all Subscriptions of the given SubscriptionFeeder' do
        subject
        expect(subscription_feeder).to have_received(:stop_all)
      end
      it 'deletes it' do
        expect { subject }.to change {
          command_queries.find_by(subscriptions_set_id: subscriptions_set_id, command_name: "StopAll")
        }.to(nil)
      end
    end

    context 'when there is a "StartAll" command' do
      let!(:command) do
        command_queries.create(subscriptions_set_id: subscriptions_set_id, command_name: "StartAll", data: {})
      end

      before do
        allow(subscription_feeder).to receive(:start_all).and_call_original
      end

      it 'starts all Subscriptions of the given SubscriptionFeeder' do
        subject
        expect(subscription_feeder).to have_received(:start_all)
      end
      it 'deletes it' do
        expect { subject }.to change {
          command_queries.find_by(subscriptions_set_id: subscriptions_set_id, command_name: "StartAll")
        }.to(nil)
      end
    end

    context 'when there is a "Restore" command' do
      let!(:command) do
        command_queries.create(subscriptions_set_id: subscriptions_set_id, command_name: "Restore", data: {})
      end

      before do
        allow(subscription_feeder).to receive(:restore).and_call_original
      end

      it 'restores SubscriptionFeeder' do
        subject
        expect(subscription_feeder).to have_received(:restore)
      end
      it 'deletes it' do
        expect { subject }.to change {
          command_queries.find_by(subscriptions_set_id: subscriptions_set_id, command_name: "Restore")
        }.to(nil)
      end
    end

    context 'when there is a "Stop" command' do
      let!(:command) do
        command_queries.create(subscriptions_set_id: subscriptions_set_id, command_name: "Stop", data: {})
      end

      before do
        allow(subscription_feeder).to receive(:stop).and_call_original
      end

      it 'stops SubscriptionFeeder' do
        subject
        expect(subscription_feeder).to have_received(:stop)
      end
      it 'deletes it' do
        expect { subject }.to change {
          command_queries.find_by(subscriptions_set_id: subscriptions_set_id, command_name: "Stop")
        }.to(nil)
      end
    end

    context 'when there is an unhandled command' do
      let!(:command) do
        command_queries.create(subscriptions_set_id: subscriptions_set_id, command_name: "FooCmd", data: {})
      end

      it 'deletes it' do
        expect { subject }.to change {
          command_queries.find_by(subscriptions_set_id: subscriptions_set_id, command_name: "FooCmd")
        }.to(nil)
      end
    end

    context 'when non-existing config_name is given' do
      let(:config_name) { :non_existing_config }

      it 'raises error' do
        expect { subject }.to raise_error(/Could not find #{:non_existing_config.inspect} config/)
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe PgEventstore::CommandsHandler do
  let(:instance) { described_class.new(config_name, feeder, runners) }
  let(:config_name) { :default }
  let(:feeder) do
    PgEventstore::SubscriptionFeeder.new(
      config_name: config_name,
      subscriptions_set_lifecycle: subscriptions_set_lifecycle,
      subscriptions_lifecycle: subscriptions_lifecycle
    )
  end
  let(:subscriptions_set_lifecycle) do
    PgEventstore::SubscriptionsSetLifecycle.new(
      config_name,
      { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
    )
  end
  let(:subscriptions_lifecycle) do
    PgEventstore::SubscriptionsLifecycle.new(config_name, subscriptions_set_lifecycle)
  end
  let(:runners) { [runner] }
  let(:runner) do
    PgEventstore::SubscriptionRunner.new(
      stats: PgEventstore::SubscriptionHandlerPerformance.new,
      events_processor: PgEventstore::EventsProcessor.new(proc {}, graceful_shutdown_timeout: 5),
      subscription: SubscriptionsHelper.create_with_connection
    )
  end

  describe 'async action' do
    subject { instance.start }

    let!(:feeder_command) do
      feeder_command_queries.create(
        subscriptions_set_id: subscriptions_set_lifecycle.persisted_subscriptions_set.id,
        command_name: 'StopAll',
        data: {}
      )
    end
    let!(:runner_command) do
      runner_command_queries.create(
        subscription_id: runner.id,
        subscriptions_set_id: subscriptions_set_lifecycle.persisted_subscriptions_set.id,
        command_name: 'Stop',
        data: {}
      )
    end

    let(:feeder_command_queries) { PgEventstore::SubscriptionsSetCommandQueries.new(PgEventstore.connection) }
    let(:runner_command_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    before do
      allow(feeder).to receive(:stop_all).and_call_original
      allow(runner).to receive(:stop_async).and_call_original
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'processes commands asynchronous' do
      subject
      aggregate_failures do
        expect(feeder).not_to have_received(:stop_all)
        expect(runner).not_to have_received(:stop_async)
        sleep described_class::PULL_INTERVAL + 0.2
        # After a second we perform the same test over the same objects, but with different expectation to prove
        # that the action is actually asynchronous
        expect(feeder).to have_received(:stop_all)
        expect(runner).to have_received(:stop_async)
      end
    end

    context 'when feeder was restarted' do
      let(:another_runner_command) do
        runner_command_queries.create(
          subscription_id: runner.id,
          subscriptions_set_id: subscriptions_set_lifecycle.persisted_subscriptions_set.id,
          command_name: 'Restore',
          data: {}
        )
      end

      before do
        instance # persist instance into memory to demonstrate the same instance acts properly in this scenario
        feeder.start.stop_async.wait_for_finish.start
        # Prepare runner to be in "stopped" state to be able to trigger "Restore" command
        runner.start.stop_async.wait_for_finish
        allow(runner).to receive(:restore).and_call_original
        another_runner_command
      end

      after do
        feeder.stop_async.wait_for_finish
        runner.stop_async.wait_for_finish
      end

      it 'does not run commands from previous run' do
        subject
        sleep described_class::PULL_INTERVAL + 0.2
        aggregate_failures do
          expect(feeder).not_to have_received(:stop_all)
          expect(runner).not_to have_received(:stop_async)
        end
      end
      it 'runs the command from current run' do
        subject
        sleep described_class::PULL_INTERVAL + 0.2
        expect(runner).to have_received(:restore)
      end
    end
  end
end

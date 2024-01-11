# frozen_string_literal: true

RSpec.describe PgEventstore::CommandsHandler do
  let(:instance) { described_class.new(config_name, feeder, runners) }
  let(:config_name) { :default }
  let(:feeder) { PgEventstore::SubscriptionFeeder.new(config_name, 'MySubscriptionsSet') }
  let(:runners) { [runner] }
  let(:runner) do
    PgEventstore::SubscriptionRunner.new(
      stats: PgEventstore::SubscriptionHandlerPerformance.new,
      events_processor: PgEventstore::EventsProcessor.new(proc { }),
      subscription: SubscriptionsHelper.create_with_connection
    )
  end

  describe 'async action' do
    subject { instance.start }

    let!(:feeder_command) do
      feeder_command_queries.create_by(subscriptions_set_id: feeder.id, command_name: 'StopAll')
    end
    let!(:runner_command) do
      runner_command_queries.create_by(subscription_id: runner.id, command_name: 'StopRunner')
    end

    let(:feeder_command_queries) { PgEventstore::SubscriptionsSetCommandQueries.new(PgEventstore.connection) }
    let(:runner_command_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    before do
      allow(feeder).to receive(:stop_all).and_call_original
      allow(runner).to receive(:stop_async).and_call_original
    end

    after do
      instance.stop
    end

    it 'processes commands asynchronous' do
      subject
      aggregate_failures do
        expect(feeder).not_to have_received(:stop_all)
        expect(runner).not_to have_received(:stop_async)
        sleep 1.2
        # After a second we perform the same test over the same objects, but with different expectation to prove
        # that the action is actually asynchronous
        expect(feeder).to have_received(:stop_all)
        expect(runner).to have_received(:stop_async)
      end
    end
  end

  describe 'auto restart' do
    subject { instance.start }

    before do
      stub_const("#{described_class}::RESTART_DELAY", 1)
      should_raise = true
      allow(instance).to receive(:subscription_feeder_commands).and_wrap_original do |original_method, *args, **kwargs, &blk|
        if should_raise
          should_raise = false
          raise "Something went wrong!"
        end
        original_method.call(*args, **kwargs, &blk)
      end
    end

    after do
      instance.stop
    end

    it 'restarts the runner after RESTART_DELAY seconds' do
      subject
      aggregate_failures do
        expect(instance.state).to eq("running")
        sleep 1.2 # wait for runner to run async action and fail afterwards
        expect(instance.state).to eq("dead")
        sleep described_class::RESTART_DELAY
        expect(instance.state).to eq("running")
      end
    end

    describe 'error output' do
      before do
        PgEventstore.logger = Logger.new(STDOUT)
      end

      after do
        PgEventstore.logger = nil
      end

      it 'outputs the information about error' do
        expect { subject; sleep 1.2 }.to output(/Error occurred:/).to_stdout_from_any_process
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeeder do
  let(:instance) do
    described_class.new(
      config_name: config_name,
      subscriptions_set_lifecycle: subscriptions_set_lifecycle,
      subscriptions_lifecycle: subscriptions_lifecycle
    )
  end
  let(:subscriptions_set_lifecycle) do
    PgEventstore::SubscriptionsSetLifecycle.new(
      config_name, { name: set_name, max_restarts_number: max_retries, time_between_restarts: retries_interval }
    )
  end
  let(:subscriptions_lifecycle) do
    PgEventstore::SubscriptionsLifecycle.new(config_name, subscriptions_set_lifecycle)
  end

  let(:config_name) { :default }
  let(:set_name) { 'FooSet' }
  let(:max_retries) { 0 }
  let(:retries_interval) { 0 }

  describe '#start_all' do
    subject { instance.start_all }

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: SubscriptionsHelper.init_with_connection
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: SubscriptionsHelper.init_with_connection(name: 'Bar')
      )
    end
    let(:setup_subscription_runners) do
      allow(subscription_runner1).to receive(:start).and_call_original
      allow(subscription_runner2).to receive(:start).and_call_original
    end

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1)
      subscriptions_lifecycle.runners.push(subscription_runner2)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    shared_examples 'runners are starting' do
      it 'returns self' do
        is_expected.to eq(instance)
      end
      it 'starts runners' do
        subject
        aggregate_failures do
          expect(subscription_runner1).to have_received(:start)
          expect(subscription_runner2).to have_received(:start)
        end
      end
    end

    shared_examples 'runners does not start' do
      it 'returns self' do
        is_expected.to eq(instance)
      end
      it 'does not start runners' do
        subject
        aggregate_failures do
          expect(subscription_runner1).not_to have_received(:start)
          expect(subscription_runner2).not_to have_received(:start)
        end
      end
    end

    context "when feeder's runner is in the 'initial' state" do
      before { setup_subscription_runners }

      it_behaves_like 'runners does not start'
      it { expect(instance.state).to eq('initial') }
    end

    context "when feeder's runner is in the 'running' state" do
      before do
        instance.start
        setup_subscription_runners
      end

      it_behaves_like 'runners are starting'
      it { expect(instance.state).to eq('running') }
    end

    context "when feeder's runner is in the 'stopped' state" do
      before do
        instance.start.stop_async.wait_for_finish
        setup_subscription_runners
      end

      it_behaves_like 'runners does not start'
      it { expect(instance.state).to eq('stopped') }
    end

    context "when feeder's runner is in the 'dead' state" do
      before do
        allow(PgEventstore::SubscriptionFeederHandlers).to receive(:ping_subscriptions_set).and_raise('Oops!')
        instance.start
        dv(instance).wait_until(timeout: 1.1) { _1.state == 'dead' }
        setup_subscription_runners
      end

      it_behaves_like 'runners does not start'
      it { expect(instance.state).to eq('dead') }
    end

    context "when feeder's runner is in the 'halting' state" do
      before do
        binding
        instance.start
        dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
        instance.stop_async
        setup_subscription_runners
      end

      it_behaves_like 'runners does not start'
      it { expect(instance.state).to eq('halting') }
    end
  end

  describe '#stop_all' do
    subject { instance.stop_all }

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: SubscriptionsHelper.init_with_connection
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: SubscriptionsHelper.init_with_connection(name: 'Bar')
      )
    end
    let(:setup_subscription_runners) do
      allow(subscription_runner1).to receive(:stop_async).and_call_original
      allow(subscription_runner2).to receive(:stop_async).and_call_original
    end

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1)
      subscriptions_lifecycle.runners.push(subscription_runner2)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    shared_examples 'runners are stopping' do
      it 'returns self' do
        is_expected.to eq(instance)
      end
      it 'starts runners' do
        subject
        aggregate_failures do
          expect(subscription_runner1).to have_received(:stop_async)
          expect(subscription_runner2).to have_received(:stop_async)
        end
      end
    end

    shared_examples 'runners does not stop' do
      it 'returns self' do
        is_expected.to eq(instance)
      end
      it 'does not start runners' do
        subject
        aggregate_failures do
          expect(subscription_runner1).not_to have_received(:stop_async)
          expect(subscription_runner2).not_to have_received(:stop_async)
        end
      end
    end

    context "when feeder's runner is in the 'initial' state" do
      before { setup_subscription_runners }

      it_behaves_like 'runners does not stop'
      it { expect(instance.state).to eq('initial') }
    end

    context "when feeder's runner is in the 'running' state" do
      before do
        instance.start
        setup_subscription_runners
      end

      after do
        instance.stop_async.wait_for_finish
      end

      it_behaves_like 'runners are stopping'
      it { expect(instance.state).to eq('running') }
    end

    context "when feeder's runner is in the 'stopped' state" do
      before do
        instance.start.stop_async.wait_for_finish
        setup_subscription_runners
      end

      it_behaves_like 'runners does not stop'
      it { expect(instance.state).to eq('stopped') }
    end

    context "when feeder's runner is in the 'dead' state" do
      before do
        allow(PgEventstore::SubscriptionFeederHandlers).to receive(:ping_subscriptions_set).and_raise('Oops!')
        instance.start
        # Let the feeder's runner die
        dv(instance).wait_until(timeout: 1.1) { _1.state == 'dead' }
        setup_subscription_runners
      end

      after do
        instance.stop_async.wait_for_finish
      end

      it_behaves_like 'runners does not stop'
      it { expect(instance.state).to eq('dead') }
    end

    context "when feeder's runner is in the 'halting' state" do
      before do
        binding
        instance.start
        dv(instance).wait_until(timeout: 1.1) { _1.state == 'running' }
        instance.stop_async
        setup_subscription_runners
      end

      after do
        instance.wait_for_finish
      end

      it_behaves_like 'runners does not stop'
      it { expect(instance.state).to eq('halting') }
    end
  end

  describe 'on state changed' do
    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    after do
      instance.stop_async.wait_for_finish
    end

    context 'when related SubscriptionsSet does not exist yet' do
      subject { instance.start }

      it 'creates it' do
        expect { subject }.to change { queries.find_all(name: set_name).size }.by(1)
      end
      it 'updates its #state' do
        expect { subject }.to change { queries.find_by(name: set_name)&.dig(:state) }.to('running')
      end
    end

    context 'when related SubscriptionsSet already exists' do
      subject { instance.restore }

      before do
        allow(PgEventstore::SubscriptionFeederHandlers).to receive(:ping_subscriptions_set).and_raise('gg wp')
        instance.start
        sleep 1.1 # Let the feeder's runner die
      end

      it 'does not create new one' do
        expect { subject }.not_to change { queries.find_all(name: set_name).size }
      end
      it 'updates related SubscriptionsSet state' do
        expect { subject }.to change { queries.find_by(name: set_name)[:state] }.from('dead').to('running')
      end
    end
  end

  describe 'on before runner started' do
    subject { instance.start }

    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }
    let(:subscription_queries) { PgEventstore::SubscriptionQueries.new(PgEventstore.connection) }

    let(:subscription1) { SubscriptionsHelper.init_with_connection(name: 'Foo', set: set_name) }
    let(:subscription2) { SubscriptionsHelper.init_with_connection(name: 'Bar', set: set_name) }

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: subscription1
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: subscription2
      )
    end
    let(:subscription_cmd_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1)
      subscriptions_lifecycle.runners.push(subscription_runner2)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'creates SubscriptionsSet' do
      expect { subject }.to change { queries.find_all(name: set_name).size }.by(1)
    end
    it 'updates SubscriptionsSet #state' do
      expect { subject }.to change { queries.find_by(name: set_name)&.dig(:state) }.to('running')
    end
    it 'locks first subscription' do
      expect { subject }.to change {
        subscription_queries.find_by(name: subscription1.name, set: set_name)&.dig(:locked_by)
      }.to(kind_of(Integer))
    end
    it 'locks second subscription' do
      expect { subject }.to change {
        subscription_queries.find_by(name: subscription2.name, set: set_name)&.dig(:locked_by)
      }.to(kind_of(Integer))
    end
    it 'starts first Subscription runner' do
      expect { subject }.to change { subscription_runner1.running? }.to(true)
    end
    it 'starts second Subscription runner' do
      expect { subject }.to change { subscription_runner2.running? }.to(true)
    end
    it 'locks subscriptions with the related SubscriptionsSet' do
      subject
      aggregate_failures do
        expect(subscription1.reload.locked_by).to eq(queries.find_by(name: set_name)[:id])
        expect(subscription2.reload.locked_by).to eq(queries.find_by(name: set_name)[:id])
      end
    end

    it 'starts CommandsHandler' do
      id = subscription_queries.create(set: set_name, name: subscription2.name)[:id]
      subscriptions_set_id = subscriptions_set_lifecycle.persisted_subscriptions_set.id
      subscription_cmd_queries.create(
        subscription_id: id, subscriptions_set_id: subscriptions_set_id, command_name: 'Stop', data: {}
      )
      expect { subject }.to change {
        dv(subscription_runner2).deferred_wait(timeout: 2) { _1.state == 'stopped' }.state
      }.to('stopped')
    end

    context 'when second Subscription is already locked' do
      let(:subscriptions_set_id) { queries.create(name: set_name)[:id] }

      before do
        subscription_queries.create(set: subscription2.set, name: subscription2.name, locked_by: subscriptions_set_id)
      end

      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::SubscriptionAlreadyLockedError)
      end
      it 'does not leave stale SubscriptionsSet records' do
        expect {
          begin
            subject
          rescue PgEventstore::SubscriptionAlreadyLockedError
          end
        }.not_to change { queries.find_all(name: set_name).size }
      end
    end
  end

  describe "on runner's death" do
    subject do
      instance.start
      sleep 1
    end

    let(:subscription_runner) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(
          proc { |event| processed_events.push(event) }, graceful_shutdown_timeout: 5
        ),
        subscription: SubscriptionsHelper.init_with_connection(set: set_name)
      )
    end
    let(:processed_events) { [] }
    let!(:event) do
      stream = PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'SomeStream', stream_id: '1')
      PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new(id: SecureRandom.uuid))
    end

    let(:error) { StandardError.new('gg wp') }
    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }
    let(:max_retries) { 1 }

    before do
      subscriptions_lifecycle.runners.push(subscription_runner)

      should_raise = true
      error = self.error
      allow(PgEventstore::SubscriptionFeederHandlers).to receive(:ping_subscriptions_set).and_wrap_original do |orig_meth, *args, **kwargs, &blk|
        if should_raise
          should_raise = false
          raise error
        end
        orig_meth.call(*args, **kwargs, &blk)
      end
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it "persists error's info into SubscriptionsSet" do
      aggregate_failures do
        expect { subject }.to change {
          queries.find_by(name: set_name)&.dig(:last_error)
        }.to(instance_of(Hash))
        expect(queries.find_by(name: set_name)&.dig(:last_error)).to(
          include('class' => 'StandardError', 'message' => 'gg wp')
        )
      end
    end
    it "updates SubscriptionsSet#last_error_occurred_at" do
      expect { subject }.to change {
        queries.find_by(name: set_name)&.dig(:last_error_occurred_at)
      }.to(be_between(Time.now.utc, Time.now.utc + 2))
    end
    it "restarts the feeder's runner" do
      subject
      expect(instance.state).to eq('running')
    end
    it 'processes events' do
      expect { subject }.to change { processed_events }.to([a_hash_including('id' => event.id)])
    end

    context 'when max number of restarts is reached' do
      let(:max_retries) { 0 }

      it "does not restart the feeder's runner" do
        subject
        expect(instance.state).to eq('dead')
      end
      it 'does process events' do
        expect {
          subject
          sleep 1.1 # Sleep an additional second to prevent false-positive result
        }.not_to change { processed_events }
      end
    end
  end

  describe 'on before runner restored' do
    subject do
      instance.start
      sleep 1.1 # Let the feeder's runner restart
    end

    let(:error) { StandardError.new('gg wp') }
    let(:max_retries) { 1 }
    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    before do
      allow(PgEventstore::SubscriptionFeederHandlers).to receive(:ping_subscriptions_set).and_raise(error)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'updates Subscription#last_restarted_at' do
      expect { subject }.to change {
        queries.find_by(name: set_name)&.dig(:last_restarted_at)
      }.to(be_between(Time.now.utc, Time.now.utc + 2))
    end
    it 'updates Subscription#restart_count' do
      expect { subject }.to change { queries.find_by(name: set_name)&.dig(:restart_count) }.to(max_retries)
    end
  end

  describe 'processing async action' do
    subject { instance.start }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'bar') }
    let(:event1) { PgEventstore::Event.new(data: { foo: :bar }, type: 'Foo') }
    let(:event2) { PgEventstore::Event.new(data: { bar: :baz }, type: 'Bar') }

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(
          proc { |raw_event| processed_events1.push(raw_event) }, graceful_shutdown_timeout: 5
        ),
        subscription: SubscriptionsHelper.create_with_connection(options: { filter: { event_types: ['Bar'] } })
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(
          proc { |raw_event| processed_events2.push(raw_event) }, graceful_shutdown_timeout: 5
        ),
        subscription: SubscriptionsHelper.create_with_connection(
          name: 'sub2', options: { filter: { event_types: ['Baz'] } }
        )
      )
    end
    let(:processed_events1) { [] }
    let(:processed_events2) { [] }

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1)
      subscriptions_lifecycle.runners.push(subscription_runner2)
      stub_const("PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL", 1.5)
      stub_const("PgEventstore::SubscriptionsSetLifecycle::HEARTBEAT_INTERVAL", 1.5)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'processes matching events' do
      subject
      PgEventstore.client.append_to_stream(stream, [event1, event2])
      # Let subscriptions process events
      dv(processed_events1).wait_until(timeout: 1.5) { _1.size == 1 }
      aggregate_failures do
        expect(processed_events1).to match_array([a_hash_including('data' => { 'bar' => 'baz' })])
        expect(processed_events2).to eq([])
      end
    end
    it 'updates SubscriptionsSet#updated_at' do
      subject
      expect { sleep 2 }.to change { subscriptions_set_lifecycle.subscriptions_set.updated_at }
    end
    it 'does not update SubscriptionsSet#updated_at too often' do
      subject
      expect { sleep 1 }.to change {
        subscriptions_set_lifecycle.subscriptions_set.updated_at
      }.to(be_between(Time.now, Time.now + 0.3))
    end
    it 'updates Subscription#updated_at of running Subscription' do
      subject
      expect { sleep 2 }.to change { subscription_runner1.subscription.updated_at }
    end
    it 'does not Subscription#updated_at of running Subscription too often' do
      subject
      expect { sleep 0.5 }.not_to change { subscription_runner1.subscription.updated_at }
    end
    it 'does not update Subscription#updated_at of stopped Subscription' do
      subject
      subscription_runner2.stop
      expect { sleep 2 }.not_to change { subscription_runner2.subscription.updated_at }
    end
  end

  describe 'on after runner stopped' do
    subject { instance.stop_async.wait_for_finish }

    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }
    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Foo')
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Bar')
      )
    end
    let(:subscription_cmd_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1)
      subscriptions_lifecycle.runners.push(subscription_runner2)
      allow(subscription_runner1).to receive(:stop_async).and_call_original
      allow(subscription_runner2).to receive(:stop_async).and_call_original
      instance.start
    end

    it 'deletes SubscriptionsSet' do
      expect { subject }.to change { queries.find_all(name: set_name).size }.by(-1)
    end
    it 'unlocks first Subscription' do
      expect { subject }.to change { subscription_runner1.subscription.reload.locked_by }.to(nil)
    end
    it 'unlocks second Subscription' do
      expect { subject }.to change { subscription_runner2.subscription.reload.locked_by }.to(nil)
    end
    it 'stops SubscriptionRunner-s gracefully' do
      subject
      aggregate_failures do
        expect(subscription_runner1).to have_received(:stop_async)
        expect(subscription_runner2).to have_received(:stop_async)
        expect(subscription_runner1.state).to eq('stopped')
        expect(subscription_runner2.state).to eq('stopped')
      end
    end
    it 'stops CommandsHandler' do
      subject
      subscriptions_set_id = subscriptions_set_lifecycle.persisted_subscriptions_set.id
      cmd = subscription_cmd_queries.create(
        subscription_id: subscription_runner2.id,
        subscriptions_set_id: subscriptions_set_id,
        command_name: 'Start',
        data: {}
      )
      cmd_lookup_attrs = {
        subscription_id: cmd.subscription_id,
        subscriptions_set_id: cmd.subscriptions_set_id,
        command_name: cmd.name
      }
      # Wait until the created command is consumed
      dv.wait_until(timeout: 1.1) { subscription_cmd_queries.find_by(**cmd_lookup_attrs).nil? }
      expect(subscription_runner2.state).to eq('stopped')
    end
  end

  describe 'on after runner stopped when stopping via command' do
    subject do
      subscriptions_set_id = subscriptions_set_lifecycle.persisted_subscriptions_set.id
      cmd = set_cmd_queries.create(subscriptions_set_id: subscriptions_set_id, command_name: 'Stop', data: {})
      cmd_lookup_attrs = {
        subscriptions_set_id: cmd.subscriptions_set_id,
        command_name: cmd.name
      }
      # Wait until the created command is consumed
      dv.wait_until(timeout: PgEventstore::CommandsHandler::PULL_INTERVAL * 2) do
        set_cmd_queries.find_by(**cmd_lookup_attrs).nil?
      end
    end

    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }
    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Foo')
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }, graceful_shutdown_timeout: 5),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Bar')
      )
    end
    let(:set_cmd_queries) { PgEventstore::SubscriptionsSetCommandQueries.new(PgEventstore.connection) }
    let(:subscription_cmd_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1)
      subscriptions_lifecycle.runners.push(subscription_runner2)
      allow(subscription_runner1).to receive(:stop_async).and_call_original
      allow(subscription_runner2).to receive(:stop_async).and_call_original
      instance.start
    end

    it 'deletes SubscriptionsSet' do
      expect { subject }.to change { queries.find_all(name: set_name).size }.by(-1)
    end
    it 'unlocks first Subscription' do
      expect { subject }.to change { subscription_runner1.subscription.reload.locked_by }.to(nil)
    end
    it 'unlocks second Subscription' do
      expect { subject }.to change { subscription_runner2.subscription.reload.locked_by }.to(nil)
    end
    it 'stops SubscriptionRunner-s gracefully' do
      subject
      aggregate_failures do
        expect(subscription_runner1).to have_received(:stop_async)
        expect(subscription_runner2).to have_received(:stop_async)
        expect(subscription_runner1.state).to eq('stopped')
        expect(subscription_runner2.state).to eq('stopped')
      end
    end
    it 'stops CommandsHandler' do
      subject
      subscriptions_set_id = subscriptions_set_lifecycle.persisted_subscriptions_set.id
      # We create a subscription command here and wait for some time. But since CommandsHandler was already stopped -
      # this subscription command should never trigger a start of the given subscription. Thus, subscription_runner2
      # should remain stopped.
      subscription_cmd_queries.create(
        subscription_id: subscription_runner2.id,
        subscriptions_set_id: subscriptions_set_id,
        command_name: 'Start',
        data: {}
      )
      sleep 1.1
      expect(subscription_runner2.state).to eq('stopped')
    end
  end
end

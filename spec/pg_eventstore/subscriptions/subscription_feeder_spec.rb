# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeeder do
  let(:instance) do
    described_class.new(config_name: config_name, set_name: set_name, max_retries: max_retries, retries_interval: 0)
  end
  let(:config_name) { :default }
  let(:set_name) { 'FooSet' }
  let(:max_retries) { 0 }
  let(:retries_interval) { 0 }

  describe '#add' do
    subject { instance.add(subscription_runner) }

    let(:subscription_runner) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.init_with_connection
      )
    end

    context "when feeder's runner is in the 'initial' state" do
      it 'adds the subscription runner' do
        expect { subject }.to change { instance.instance_variable_get(:@runners) }.from([]).to([subscription_runner])
      end
      it 'returns added runner' do
        is_expected.to eq(subscription_runner)
      end
    end

    context "when feeder's runner is in the 'running' state" do
      before do
        instance.start
      end

      after do
        instance.stop_async.wait_for_finish
      end

      it 'raises error' do
        aggregate_failures do
          expect { subject }.to raise_error(/Could not add subscription/)
          expect(instance.state).to eq('running')
        end
      end
    end

    context "when feeder's runner is in the 'stopped' state" do
      before do
        instance.start.stop_async.wait_for_finish
      end

      it 'adds the subscription runner' do
        aggregate_failures do
          expect { subject }.to change { instance.instance_variable_get(:@runners) }.from([]).to([subscription_runner])
          expect(instance.state).to eq('stopped')
        end
      end
      it 'returns added runner' do
        is_expected.to eq(subscription_runner)
      end
    end

    context "when feeder's runner is in the 'dead' state" do
      before do
        allow(instance).to receive(:feeder).and_raise('Oops!')
        instance.start
        sleep 1.1 # Let the feeder's runner die
      end

      it 'raises error' do
        aggregate_failures do
          expect { subject }.to raise_error(/Could not add subscription/)
          expect(instance.state).to eq('dead')
        end
      end
    end

    context "when feeder's runner is in the 'halting' state" do
      before do
        instance.start
        sleep 0.1
        instance.stop_async
      end

      after do
        instance.wait_for_finish
      end

      it 'raises error' do
        aggregate_failures do
          expect { subject }.to raise_error(/Could not add subscription/)
          expect(instance.state).to eq('halting')
        end
      end
    end
  end

  describe '#start_all' do
    subject { instance.start_all }

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.init_with_connection
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.init_with_connection(name: 'Bar')
      )
    end
    let(:setup_subscription_runners) do
      allow(subscription_runner1).to receive(:start).and_call_original
      allow(subscription_runner2).to receive(:start).and_call_original
    end

    before do
      instance.add(subscription_runner1)
      instance.add(subscription_runner2)
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

      after do
        instance.stop_async.wait_for_finish
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
        allow(instance).to receive(:feeder).and_raise('Oops!')
        instance.start
        sleep 1.1 # Let the feeder's runner die
        setup_subscription_runners
      end

      after do
        instance.stop_async.wait_for_finish
      end

      it_behaves_like 'runners does not start'
      it { expect(instance.state).to eq('dead') }
    end

    context "when feeder's runner is in the 'halting' state" do
      before do
        binding
        instance.start
        sleep 0.1
        instance.stop_async
        setup_subscription_runners
      end

      after do
        instance.wait_for_finish
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
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.init_with_connection
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.init_with_connection(name: 'Bar')
      )
    end
    let(:setup_subscription_runners) do
      allow(subscription_runner1).to receive(:stop_async).and_call_original
      allow(subscription_runner2).to receive(:stop_async).and_call_original
    end

    before do
      instance.add(subscription_runner1)
      instance.add(subscription_runner2)
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
        allow(instance).to receive(:feeder).and_raise('Oops!')
        instance.start
        sleep 1.1 # Let the feeder's runner die
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
        sleep 0.1
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

  describe '#force_lock!' do
    subject { instance.force_lock! }

    it 'sets @force_lock flag to true' do
      expect { subject }.to change { instance.instance_variable_get(:@force_lock) }.to(true)
    end
  end

  describe '#read_only_subscriptions' do
    subject { instance.read_only_subscriptions }

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.init_with_connection(name: 'Foo')
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.init_with_connection(name: 'Bar')
      )
    end

    before do
      instance.add(subscription_runner1)
      instance.add(subscription_runner2)
    end

    it 'returns the copies of the given subscriptions without bound connection' do
      aggregate_failures do
        expect(subject.map(&:options_hash)).to(
          eq([subscription_runner1.subscription.options_hash, subscription_runner2.subscription.options_hash])
        )
        expect { subject.first.reload }.to raise_error(RuntimeError, /No connection was set/)
        expect { subject.last.reload }.to raise_error(RuntimeError, /No connection was set/)
      end
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
        allow(instance).to receive(:feeder).and_raise('gg wp')
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
    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Foo')
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Bar')
      )
    end
    let(:subscription_cmd_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    before do
      instance.add(subscription_runner1)
      instance.add(subscription_runner2)
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
        subscription_runner1.subscription.reload.locked_by
      }.to(kind_of(Integer))
    end
    it 'locks second subscription' do
      expect { subject }.to change {
        subscription_runner2.subscription.reload.locked_by
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
        expect(subscription_runner1.subscription.reload.locked_by).to eq(queries.find_by(name: set_name)[:id])
        expect(subscription_runner2.subscription.reload.locked_by).to eq(queries.find_by(name: set_name)[:id])
      end
    end
    it 'starts CommandsHandler' do
      subscription_cmd_queries.create(
        subscription_id: subscription_runner2.id, subscriptions_set_id: instance.id, command_name: 'Stop'
      )
      expect { subject; sleep 2 }.to change { subscription_runner2.state }.to('stopped')
    end
  end

  describe "on runner's death" do
    subject do
      instance.start
      sleep 1
    end

    let(:error) { StandardError.new('gg wp') }
    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }
    let(:max_retries) { 1 }
    let(:runners_feeder) { PgEventstore::SubscriptionRunnersFeeder.new(:default) }

    before do
      should_raise = true
      error = self.error
      allow(PgEventstore::SubscriptionRunnersFeeder).to receive(:new).and_return(runners_feeder)
      allow(runners_feeder).to receive(:feed).and_call_original
      allow(instance).to receive(:feeder).and_wrap_original do |orig_meth, *args, **kwargs, &blk|
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
    it 'feeds subscription runners' do
      subject
      expect(runners_feeder).to have_received(:feed).at_least(:once)
    end

    context 'when max number of restarts is reached' do
      let(:max_retries) { 0 }

      it "does not restart the feeder's runner" do
        subject
        expect(instance.state).to eq('dead')
      end
      it 'does not feed subscription runners' do
        subject
        sleep 1.1 # Sleep an additional second to prevent false-positive result
        expect(runners_feeder).not_to have_received(:feed)
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
      allow(instance).to receive(:feeder).and_raise(error)
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
        events_processor: PgEventstore::EventsProcessor.new(proc { |raw_event| events_receiver.call(raw_event) }),
        subscription: SubscriptionsHelper.create_with_connection(options: { filter: { event_types: ['Bar'] } })
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { |raw_event| events_receiver.call(raw_event) }),
        subscription: SubscriptionsHelper.create_with_connection(
          name: 'sub2', options: { filter: { event_types: ['Baz'] } }
        )
      )
    end
    let(:events_receiver) { double('Events receiver') }

    before do
      allow(events_receiver).to receive(:call)
      instance.add(subscription_runner1)
      instance.add(subscription_runner2)
      stub_const("#{described_class}::HEARTBEAT_INTERVAL", 1.5)
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'processes matching events' do
      subject
      PgEventstore.client.append_to_stream(stream, [event1, event2])
      sleep 1.5 # Let everything to start and process events
      aggregate_failures do
        expect(events_receiver).to have_received(:call).with(a_hash_including('data' => { 'bar' => 'baz' }))
        expect(events_receiver).not_to have_received(:call).with(a_hash_including('data' => { 'foo' => 'bar' }))
      end
    end
    it 'updates SubscriptionsSet#updated_at' do
      subject
      expect { sleep 2 }.to change { instance.read_only_subscriptions_set.updated_at }
    end
    it 'does not update SubscriptionsSet#updated_at too often' do
      subject
      expect { sleep 0.5 }.not_to change { instance.read_only_subscriptions_set.updated_at }
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
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Foo')
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Bar')
      )
    end
    let(:subscription_cmd_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    before do
      instance.add(subscription_runner1)
      instance.add(subscription_runner2)
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
      subscription_cmd_queries.create(
        subscription_id: subscription_runner2.id, subscriptions_set_id: instance.id, command_name: 'Start'
      )
      sleep 1.1
      expect(subscription_runner2.state).to eq('stopped')
    end
  end

  describe 'on after runner stopped when stopping via command' do
    subject do
      set_cmd_queries.create(
        subscriptions_set_id: instance.id, command_name: 'Stop'
      )
      sleep PgEventstore::CommandsHandler::PULL_INTERVAL * 2
    end

    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }
    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Foo')
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Bar')
      )
    end
    let(:set_cmd_queries) { PgEventstore::SubscriptionsSetCommandQueries.new(PgEventstore.connection) }
    let(:subscription_cmd_queries) { PgEventstore::SubscriptionCommandQueries.new(PgEventstore.connection) }

    before do
      instance.add(subscription_runner1)
      instance.add(subscription_runner2)
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
      subscription_cmd_queries.create(
        subscription_id: subscription_runner2.id, subscriptions_set_id: instance.id, command_name: 'Start'
      )
      sleep 1.1
      expect(subscription_runner2.state).to eq('stopped')
    end
  end
end

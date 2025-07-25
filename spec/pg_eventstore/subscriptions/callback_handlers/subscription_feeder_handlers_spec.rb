# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeederHandlers do
  it { is_expected.to be_a(PgEventstore::Extensions::CallbackHandlersExtension) }

  describe '.update_subscriptions_set_state' do
    subject { described_class.update_subscriptions_set_state(subscriptions_set_lifecycle, state) }

    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        name: 'Foo', max_restarts_number: 0, time_between_restarts: 0
      )
    end
    let(:state) { 'halting' }

    it 'updates SubscriptionsSet#state' do
      expect { subject }.to change { subscriptions_set_lifecycle.persisted_subscriptions_set.reload.state }.to(state)
    end
  end

  describe '.lock_subscriptions' do
    subject { described_class.lock_subscriptions(subscriptions_lifecycle) }

    let(:subscriptions_lifecycle) do
      PgEventstore::SubscriptionsLifecycle.new(:default, subscriptions_set_lifecycle)
    end
    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc {}, graceful_shutdown_timeout: 0),
        subscription: subscription1
      )
    end
    let(:subscription1) { SubscriptionsHelper.init_with_connection(set: 'Foo', name: 'Bar') }
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc {}, graceful_shutdown_timeout: 0),
        subscription: subscription2
      )
    end
    let(:subscription2) { SubscriptionsHelper.init_with_connection(set: 'Foo', name: 'Baz') }

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1)
      subscriptions_lifecycle.runners.push(subscription_runner2)
    end

    it 'locks first subscription' do
      aggregate_failures do
        expect { subject }.to change {
          subscription1.locked_by
        }.to(subscriptions_set_lifecycle.persisted_subscriptions_set.id)
        expect(subscription1.id).to be_an(Integer)
      end

    end
    it 'locks second subscription' do
      aggregate_failures do
        expect { subject }.to change {
          subscription2.locked_by
        }.to(subscriptions_set_lifecycle.persisted_subscriptions_set.id)
        expect(subscription2.id).to be_an(Integer)
      end
    end
  end

  describe '.start_runners' do
    subject { described_class.start_runners(subscriptions_lifecycle) }

    let(:subscriptions_lifecycle) do
      PgEventstore::SubscriptionsLifecycle.new(:default, subscriptions_set_lifecycle)
    end
    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc {}, graceful_shutdown_timeout: 0),
        subscription: SubscriptionsHelper.create_with_connection(set: 'Foo', name: 'Bar')
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc {}, graceful_shutdown_timeout: 0),
        subscription: SubscriptionsHelper.create_with_connection(set: 'Foo', name: 'Baz')
      )
    end

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1)
      subscriptions_lifecycle.runners.push(subscription_runner2)
    end

    after do
      subscriptions_lifecycle.runners.each(&:stop_async).each(&:wait_for_finish)
    end

    it 'starts first runner' do
      expect { subject }.to change { subscription_runner1.state }.from('initial').to('running')
    end
    it 'starts second runner' do
      expect { subject }.to change { subscription_runner2.state }.from('initial').to('running')
    end
  end

  describe '.start_cmds_handler' do
    subject { described_class.start_cmds_handler(cmds_handler) }

    let(:cmds_handler) do
      PgEventstore::CommandsHandler.new(:default, subscription_feeder, [])
    end
    let(:subscription_feeder) do
      PgEventstore::SubscriptionFeeder.new(
        config_name: :default,
        subscriptions_set_lifecycle: subscriptions_set_lifecycle,
        subscriptions_lifecycle: subscriptions_lifecycle
      )
    end
    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end
    let(:subscriptions_lifecycle) do
      PgEventstore::SubscriptionsLifecycle.new(:default, subscriptions_set_lifecycle)
    end

    after do
      cmds_handler.stop_async.wait_for_finish
    end

    it 'starts commands handler' do
      expect { subject }.to change { cmds_handler.state }.from('initial').to('running')
    end
  end

  describe '.persist_error_info' do
    subject { described_class.persist_error_info(subscriptions_set_lifecycle, error) }

    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end
    let(:error) do
      StandardError.new("something happened").tap do |err|
        err.set_backtrace([])
      end
    end

    it 'updates SubscriptionsSet#last_error' do
      expect { subject }.to change { subscriptions_set_lifecycle.persisted_subscriptions_set.reload.last_error }.to(
        { 'class' => 'StandardError', 'message' => 'something happened', 'backtrace' => [] }
      )
    end
    it 'updates SubscriptionsSet#last_error_occurred_at', timecop: true do
      expect { subject }.to change {
        subscriptions_set_lifecycle.persisted_subscriptions_set.reload.last_error_occurred_at
      }.to(Time.now.round(6))
    end
  end

  describe '.ping_subscriptions_set' do
    subject { described_class.ping_subscriptions_set(subscriptions_set_lifecycle) }

    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 10, time_between_restarts: 0 }
      )
    end

    it 'updates SubscriptionsSet#updated_at', timecop: true do
      expect { subject }.to change {
        subscriptions_set_lifecycle.persisted_subscriptions_set.reload.updated_at
      }.to(Time.now.round(6))
    end
  end

  describe '.feed_runners' do
    subject { described_class.feed_runners(subscriptions_lifecycle, :default) }

    let(:subscriptions_lifecycle) do
      PgEventstore::SubscriptionsLifecycle.new(:default, subscriptions_set_lifecycle)
    end
    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(
          proc { |event| precessed_events1.push(event) }, graceful_shutdown_timeout: 0
        ),
        subscription: SubscriptionsHelper.create_with_connection(
          set: 'Foo',
          name: 'Bar',
          options: { filter: { event_types: ['Bar'] } }
        )
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(
          proc { |event| precessed_events2.push(event) }, graceful_shutdown_timeout: 0
        ),
        subscription: SubscriptionsHelper.create_with_connection(
          set: 'Foo',
          name: 'Baz',
          options: { filter: { event_types: ['Baz'] } }
        )
      )
    end

    let(:precessed_events1) { [] }
    let(:precessed_events2) { [] }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1') }
    let(:bar_event) do
      PgEventstore::Event.new(type: 'Bar')
    end
    let(:baz_event) do
      PgEventstore::Event.new(type: 'Baz')
    end

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1, subscription_runner2)
      subscriptions_lifecycle.runners.each(&:start)
      PgEventstore.client.append_to_stream(stream, [bar_event, baz_event, baz_event])
    end

    after do
      subscriptions_lifecycle.runners.each(&:stop_async).each(&:wait_for_finish)
    end

    it 'processes events of first subscription' do
      expect { subject }.to change {
        dv(precessed_events1).deferred_wait(timeout: 0.5) { _1.size == 1 }
      }.to([a_hash_including('type' => 'Bar')])
    end
    it 'processes events of second subscription' do
      expect { subject }.to change {
        dv(precessed_events2).deferred_wait(timeout: 0.5) { _1.size == 2 }
      }.to([a_hash_including('type' => 'Baz'), a_hash_including('type' => 'Baz')])
    end
  end

  describe '.ping_subscriptions' do
    subject { described_class.ping_subscriptions(subscriptions_lifecycle) }

    let(:subscriptions_lifecycle) do
      PgEventstore::SubscriptionsLifecycle.new(:default, subscriptions_set_lifecycle)
    end
    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc {}, graceful_shutdown_timeout: 0),
        subscription: subscription1
      )
    end
    let(:subscription1) do
      SubscriptionsHelper.create_with_connection(
        set: 'Foo', name: 'Bar', locked_by: subscriptions_set_lifecycle.persisted_subscriptions_set.id
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc {}, graceful_shutdown_timeout: 0),
        subscription: subscription2
      )
    end
    let(:subscription2) do
      SubscriptionsHelper.create_with_connection(
        set: 'Foo', name: 'Baz', locked_by: subscriptions_set_lifecycle.persisted_subscriptions_set.id
      )
    end

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1, subscription_runner2)
      subscriptions_lifecycle.runners.each(&:start)
      subscription1.update(updated_at: Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1)
      subscription2.update(updated_at: Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1)
    end

    after do
      subscriptions_lifecycle.runners.each(&:stop_async).each(&:wait_for_finish)
    end

    it 'updates #updated_at of first subscription', timecop: true do
      expect { subject }.to change { subscription1.reload.updated_at }.to(Time.now.round(6))
    end
    it 'updates #updated_at of second subscription', timecop: true do
      expect { subject }.to change { subscription2.reload.updated_at }.to(Time.now.round(6))
    end
  end

  describe '.stop_runners' do
    subject { described_class.stop_runners(subscriptions_lifecycle) }

    let(:subscriptions_lifecycle) do
      PgEventstore::SubscriptionsLifecycle.new(:default, subscriptions_set_lifecycle)
    end
    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end

    let(:subscription_runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc {}, graceful_shutdown_timeout: 0),
        subscription: SubscriptionsHelper.create_with_connection(
          set: 'Foo', name: 'Bar', locked_by: subscriptions_set_lifecycle.persisted_subscriptions_set.id
        )
      )
    end
    let(:subscription_runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc {}, graceful_shutdown_timeout: 0),
        subscription: SubscriptionsHelper.create_with_connection(
          set: 'Foo', name: 'Baz', locked_by: subscriptions_set_lifecycle.persisted_subscriptions_set.id
        )
      )
    end

    before do
      subscriptions_lifecycle.runners.push(subscription_runner1, subscription_runner2)
      subscription_runner1.start
      subscription_runner2.start
    end

    after do
      subscriptions_lifecycle.runners.each(&:stop_async).each(&:wait_for_finish)
    end

    it 'stops first runner' do
      expect { subject }.to change { subscription_runner1.state }.from("running").to("stopped")
    end
    it 'stops second runner' do
      expect { subject }.to change { subscription_runner2.state }.from("running").to("stopped")
    end
  end

  describe '.reset_subscriptions_set' do
    subject { described_class.reset_subscriptions_set(subscriptions_set_lifecycle) }

    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end
    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    before do
      # Create SubscriptionsSet
      subscriptions_set_lifecycle.persisted_subscriptions_set
    end

    it 'deletes SubscriptionsSet' do
      expect { subject }.to change { queries.find_all(name: 'Foo') }.to([])
    end
    it 'unlinks the reference on the deleted SubscriptionsSet' do
      expect { subject }.to change { subscriptions_set_lifecycle.subscriptions_set }.to(nil)
    end
  end

  describe '.stop_commands_handler' do
    subject { described_class.stop_commands_handler(cmds_handler) }

    let(:cmds_handler) do
      PgEventstore::CommandsHandler.new(:default, subscription_feeder, [])
    end
    let(:subscription_feeder) do
      PgEventstore::SubscriptionFeeder.new(
        config_name: :default,
        subscriptions_set_lifecycle: subscriptions_set_lifecycle,
        subscriptions_lifecycle: subscriptions_lifecycle
      )
    end
    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end
    let(:subscriptions_lifecycle) do
      PgEventstore::SubscriptionsLifecycle.new(:default, subscriptions_set_lifecycle)
    end

    before do
      cmds_handler.start
    end

    after do
      cmds_handler.stop_async.wait_for_finish
    end

    it 'stops commands handler' do
      expect { subject }.to change { cmds_handler.state }.from("running").to("stopped")
    end
  end

  describe '.update_subscriptions_set_restarts' do
    subject { described_class.update_subscriptions_set_restarts(subscriptions_set_lifecycle) }

    let(:subscriptions_set_lifecycle) do
      PgEventstore::SubscriptionsSetLifecycle.new(
        :default,
        { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
      )
    end

    it 'updates SubscriptionsSet#last_restarted_at', timecop: true do
      expect { subject }.to change {
        subscriptions_set_lifecycle.persisted_subscriptions_set.reload.last_restarted_at
      }.to(Time.now.round(6))
    end
    it 'updates SubscriptionsSet#restart_count' do
      expect { subject }.to change {
        subscriptions_set_lifecycle.persisted_subscriptions_set.reload.restart_count
      }.by(1)
    end
  end
end

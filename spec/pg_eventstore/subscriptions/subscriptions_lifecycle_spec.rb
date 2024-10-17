# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionsLifecycle do
  let(:instance) { described_class.new(:default, subscriptions_set_lifecycle) }
  let(:subscriptions_set_lifecycle) do
    PgEventstore::SubscriptionsSetLifecycle.new(
      :default,
      { name: 'Foo', max_restarts_number: 0, time_between_restarts: 0 }
    )
  end

  describe '#lock_all' do
    subject { instance.lock_all }

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
      instance.runners.push(subscription_runner1)
      instance.runners.push(subscription_runner2)
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

    context 'when second subscription is already locked' do
      let(:subscription1) { SubscriptionsHelper.create_with_connection(set: 'Foo', name: 'Bar') }
      let(:subscription2) do
        SubscriptionsHelper.create_with_connection(set: 'Foo', name: 'Baz', locked_by: another_subscriptions_set.id)
      end
      let(:another_subscriptions_set) { SubscriptionsSetHelper.create_with_connection(name: 'Foo') }

      before do
        # Pre-create current SubscriptionsSet
        subscriptions_set_lifecycle.persisted_subscriptions_set
      end

      it 'raises SubscriptionAlreadyLockedError error' do
        expect { subject }.to raise_error(PgEventstore::SubscriptionAlreadyLockedError)
      end
      it 'does not lock first subscription' do
        expect {
          subject rescue PgEventstore::SubscriptionAlreadyLockedError
        }.not_to change { subscription1.reload.locked_by }
      end
      it 'does not unlock second subscription' do
        expect {
          subject rescue PgEventstore::SubscriptionAlreadyLockedError
        }.not_to change { subscription2.reload.locked_by }
      end

      context 'when force lock is enabled' do
        before do
          instance.force_lock!
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
    end
  end

  describe '#ping_subscriptions' do
    subject { instance.ping_subscriptions }

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
      instance.runners.push(subscription_runner1, subscription_runner2)
      instance.runners.each(&:start)
    end

    after do
      instance.runners.each(&:stop_async).each(&:wait_for_finish)
    end

    context 'when it is a time to ping' do
      before do
        Timecop.freeze(Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1) do
          instance.ping_subscriptions
        end
      end

      context 'when both subscriptions have not been updated for a while' do
        before do
          subscription1.update(updated_at: Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1)
          subscription2.update(updated_at: Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1)
        end

        it 'updates #updated_at of first subscription', timecop: true do
          expect { subject }.to change { subscription1.reload.updated_at }.to(Time.now.round(6))
        end
        it 'updates #updated_at of second subscription', timecop: true do
          expect { subject }.to change { subscription2.reload.updated_at }.to(Time.now.round(6))
        end
      end

      context 'when first subscription has been updated recently' do
        before do
          subscription1.update(updated_at: Time.now.utc)
          subscription2.update(updated_at: Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1)
        end

        it 'does not update #updated_at of first subscription' do
          expect { subject }.not_to change { subscription1.reload.updated_at }
        end
        it 'updates #updated_at of second subscription', timecop: true do
          expect { subject }.to change { subscription2.reload.updated_at }.to(Time.now.round(6))
        end
      end

      context 'when first subscription is not running and both subscriptions have not been updated for a while' do
        before do
          subscription_runner1.stop_async.wait_for_finish
          subscription1.update(updated_at: Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1)
          subscription2.update(updated_at: Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1)
        end

        it 'does not update #updated_at of first subscription' do
          expect { subject }.not_to change { subscription1.reload.updated_at }
        end
        it 'updates #updated_at of second subscription', timecop: true do
          expect { subject }.to change { subscription2.reload.updated_at }.to(Time.now.round(6))
        end
      end
    end

    context 'when it is not a time to ping' do
      before do
        instance.ping_subscriptions
        subscription1.update(updated_at: Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1)
        subscription2.update(updated_at: Time.now.utc - PgEventstore::SubscriptionsLifecycle::HEARTBEAT_INTERVAL - 1)
      end

      it 'does not update #updated_at of first subscription' do
        expect { subject }.not_to change { subscription1.reload.updated_at }
      end
      it 'does not update #updated_at of second subscription' do
        expect { subject }.not_to change { subscription2.reload.updated_at }
      end
    end
  end

  describe '#subscriptions' do
    subject { instance.subscriptions }

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
      instance.runners.push(subscription_runner1, subscription_runner2)
    end

    it 'returns added subscriptions' do
      is_expected.to eq([subscription1, subscription2])
    end
  end

  describe '#force_lock!' do
    subject { instance.force_lock! }

    it 'force-locks the instance' do
      expect { subject }.to change { instance.force_locked? }.from(false).to(true)
    end
  end

  describe '#force_locked?' do
    subject { instance.force_locked? }

    context 'when instance is not force-locked' do
      it { is_expected.to eq(false) }
    end

    context 'when instance is force-locked' do
      before do
        instance.force_lock!
      end

      it { is_expected.to eq(true) }
    end
  end
end

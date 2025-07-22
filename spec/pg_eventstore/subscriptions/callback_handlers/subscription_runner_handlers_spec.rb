# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionRunnerHandlers do
  it { is_expected.to be_a(PgEventstore::Extensions::CallbackHandlersExtension) }

  describe '.track_exec_time' do
    subject { described_class.track_exec_time(stats, action, current_position) }

    let(:stats) { PgEventstore::SubscriptionHandlerPerformance.new }
    let(:action) { proc { sleep 0.2 } }
    let(:current_position) { 1 }

    it 'tracks execution time of the given action' do
      expect { subject }.to change { stats.average_event_processing_time }.to(be_between(0.2, 0.21))
    end
  end

  describe '.update_subscription_stats' do
    subject { described_class.update_subscription_stats(subscription, stats, current_position) }

    let(:subscription) { SubscriptionsHelper.create_with_connection(total_processed_events: 2) }
    let(:stats) { PgEventstore::SubscriptionHandlerPerformance.new }
    let(:current_position) { 123 }

    before do
      stats.track_exec_time { sleep 0.2 }
    end

    it 'updates Subscription#average_event_processing_time' do
      expect { subject }.to change { subscription.reload.average_event_processing_time }.to(be_between(0.2, 0.21))
    end
    it 'updates Subscription#current_position' do
      expect { subject }.to change { subscription.reload.current_position }.to(current_position)
    end
    it 'updates Subscription#total_processed_events' do
      expect { subject }.to change { subscription.reload.total_processed_events }.by(1)
    end
  end

  describe '.update_subscription_error' do
    subject { described_class.update_subscription_error(subscription, error) }

    let(:subscription) { SubscriptionsHelper.create_with_connection(total_processed_events: 2) }
    let(:error) { PgEventstore::WrappedException.new(original_error, { foo: 'bar' }) }
    let(:original_error) do
      StandardError.new("something happened").tap do |err|
        err.set_backtrace([])
      end
    end

    it 'updates Subscription#last_error' do
      expect { subject }.to change { subscription.reload.last_error }.to(
        { 'class' => 'StandardError', 'message' => 'something happened', 'backtrace' => [], 'foo' => 'bar' }
      )
    end
    it 'updates Subscription#last_error_occurred_at', timecop: true do
      expect { subject }.to change { subscription.reload.last_error_occurred_at }.to(Time.now.round(6))
    end
  end

  describe '.update_subscription_chunk_stats' do
    subject { described_class.update_subscription_chunk_stats(subscription, global_position) }

    let(:subscription) { SubscriptionsHelper.create_with_connection }
    let(:global_position) { 123 }

    it 'updates Subscription#last_chunk_fed_at', timecop: true do
      expect { subject }.to change { subscription.reload.last_chunk_fed_at }.to(Time.now.round(6))
    end
    it 'updates Subscription#last_chunk_greatest_position' do
      expect { subject }.to change { subscription.reload.last_chunk_greatest_position }.to(global_position)
    end
  end

  describe '.update_subscription_restarts' do
    subject { described_class.update_subscription_restarts(subscription) }

    let(:subscription) { SubscriptionsHelper.create_with_connection }

    it 'updates Subscription#last_restarted_at', timecop: true do
      expect { subject }.to change { subscription.reload.last_restarted_at }.to(Time.now.round(6))
    end
    it 'updates Subscription#restart_count' do
      expect { subject }.to change { subscription.reload.restart_count }.by(1)
    end
  end

  describe '.update_subscription_state' do
    subject { described_class.update_subscription_state(subscription, state) }

    let(:subscription) { SubscriptionsHelper.create_with_connection }
    let(:state) { 'halting' }

    it 'updates Subscription#state' do
      expect { subject }.to change { subscription.reload.state }.to(state)
    end
  end
end

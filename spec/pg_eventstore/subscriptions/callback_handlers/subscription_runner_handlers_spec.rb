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
    let(:error) do
      StandardError.new("something happened").tap do |err|
        err.set_backtrace([])
      end
    end

    it 'updates Subscription#last_error' do
      expect { subject }.to change { subscription.reload.last_error }.to(
        { 'class' => 'StandardError', 'message' => 'something happened', 'backtrace' => [] }
      )
    end
    it 'updates Subscription#last_error_occurred_at', timecop: true do
      expect { subject }.to change { subscription.reload.last_error_occurred_at }.to(Time.now.round(6))
    end
  end

  describe '.restart_events_processor' do
    subject do
      described_class.restart_events_processor(
        subscription, restart_terminator, failed_subscription_notifier, events_processor, error
      )
    end

    let(:subscription) { SubscriptionsHelper.create_with_connection(time_between_restarts: 1) }
    let(:restart_terminator) { nil }
    let(:failed_subscription_notifier) { nil }
    let(:events_processor) { PgEventstore::EventsProcessor.new(handler, graceful_shutdown_timeout: 1) }
    let(:error) { StandardError.new("something happened") }
    let(:handler) do
      should_raise = true
      proc do
        next unless should_raise

        should_raise = false
        raise error
      end
    end

    before do
      events_processor.start
      # triggers the handler, thus making the processor dead
      events_processor.feed([{ 'global_position' => 1 }])
      sleep 0.1 # give some time to process the event
    end

    after do
      events_processor.stop_async.wait_for_finish
    end

    context 'when events processor can be restarted' do
      it 'restarts it after Subscription#time_between_restarts seconds' do
        expect { subject; sleep subscription.time_between_restarts + 0.1 }.to change {
          events_processor.state
        }.from("dead").to("running")
      end
    end

    context 'when restart terminator returns true' do
      let(:restart_terminator) { proc { true } }

      it 'does not restart events processor' do
        expect { subject; sleep subscription.time_between_restarts + 0.1 }.not_to change { events_processor.state }
      end
    end

    context 'when max number of restarts has reached' do
      before do
        subscription.update(restart_count: 2, max_restarts_number: 2)
      end

      it 'does not restart events processor' do
        expect { subject; sleep subscription.time_between_restarts + 0.1 }.not_to change { events_processor.state }
      end

      context 'when failed_subscription_notifier is provided' do
        let(:failed_subscription_notifier) { proc { |subscription, error| notifier.call(subscription, error) } }
        let(:notifier) { double('Notifier') }

        before do
          allow(notifier).to receive(:call)
        end

        it 'calls it' do
          subject
          expect(notifier).to have_received(:call).with(subscription, error)
        end
        it 'does not restart events processor' do
          expect { subject; sleep subscription.time_between_restarts + 0.1 }.not_to change { events_processor.state }
        end
      end
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

# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionRunnerCommands::Restore do
  it { is_expected.to be_a(PgEventstore::SubscriptionRunnerCommands::Base) }

  describe 'attributes' do
    it { is_expected.to have_attribute(:name).with_default_value('Restore') }
  end

  describe '.known_command?' do
    subject { described_class.known_command? }

    it { is_expected.to eq(true) }
  end

  describe '#exec_cmd' do
    subject { command.exec_cmd(subscription_runner) }

    let(:command) { described_class.new }

    let(:subscription) do
      SubscriptionsHelper.create_with_connection(
        max_restarts_number: 10,
        restart_count: 10,
        last_restarted_at: Time.now - 10,
        last_error: { 'class' => 'StandardError', 'message' => 'Something went wrong', 'backtrace' => [] },
        last_error_occurred_at: Time.now - 11
      )
    end
    let(:subscription_runner) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(handler, graceful_shutdown_timeout: 5),
        subscription: subscription
      )
    end
    let(:handler) { proc {} }
    let(:processed_events) { [] }

    before do
      subscription_runner.start
      subscription_runner.feed(['global_position' => 1])
      dv(processed_events).wait_until(timeout: 0.5) { _1.size == 1 }
    end

    after do
      subscription_runner.stop_async.wait_for_finish
    end

    context 'when state is "dead"' do
      let(:handler) do
        should_raise = true
        proc do |event|
          if should_raise
            should_raise = false
            raise 'OOPS!'
          end
          processed_events.push(event)
        end
      end

      it 'restores SubscriptionRunner' do
        aggregate_failures do
          expect { subject; sleep 0.1 }.to change { subscription_runner.running? }.to(true)
          expect(processed_events.size).to eq(1)
        end
      end
      it "resets subscription's error-related attributes", :timecop do
        expect { subject }.to change { subscription.reload.options_hash }.to(
          hash_including(
            restart_count: 1,
            last_restarted_at: Time.now.round(6),
            last_error: nil,
            last_error_occurred_at: nil
          )
        )
      end
    end

    context 'when state is something else' do
      it "does not update subscription's error-related attributes" do
        expect { subject }.not_to change {
          subscription.reload.options_hash.
            slice(:restart_count, :last_restarted_at, :last_error, :last_error_occurred_at)
        }
      end
    end
  end
end

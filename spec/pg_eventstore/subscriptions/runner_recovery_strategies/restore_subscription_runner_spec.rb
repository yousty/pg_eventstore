# frozen_string_literal: true

RSpec.describe PgEventstore::RunnerRecoveryStrategies::RestoreSubscriptionRunner do
  let(:instance) do
    described_class.new(
      subscription: subscription,
      restart_terminator: restart_terminator,
      failed_subscription_notifier: failed_subscription_notifier
    )
  end
  let(:subscription) { SubscriptionsHelper.create_with_connection }
  let(:restart_terminator) { nil }
  let(:failed_subscription_notifier) { nil }

  it { expect(instance).to be_a(PgEventstore::RunnerRecoveryStrategy) }

  describe '#recovers?' do
    subject { instance.recovers?(error) }

    let(:error) { PgEventstore::Utils.wrap_exception(StandardError.new) }

    context 'when an error is WrappedException' do
      it { is_expected.to eq(true) }
    end

    context 'when an error is something else' do
      let(:error) { StandardError.new }

      it { is_expected.to eq(false) }
    end
  end

  describe '#recover' do
    subject { instance.recover(error) }

    let(:error) { PgEventstore::Utils.wrap_exception(original_error) }
    let(:original_error) { StandardError.new('something') }

    shared_examples 'recover' do
      before do
        subscription.update(time_between_restarts: 1)
      end

      it 'sleeps #time_between_restarts seconds' do
        seconds = Benchmark.realtime { subject }
        expect(seconds).to be_between(1.0, 1.1)
      end
      it { is_expected.to eq(true) }
    end

    shared_examples 'does not recover' do
      it { is_expected.to eq(false) }
      it 'does not sleep' do
        seconds = Benchmark.realtime { subject }
        expect(seconds).to be < 0.1
      end
    end

    context 'when restarts count is less than max restarts number' do
      it_behaves_like 'recover'
    end

    context 'when restarts count is greater than or equal to max restarts number' do
      before do
        subscription.update(restart_count: 1, max_restarts_number: 1)
      end

      it_behaves_like 'does not recover'

      context 'when failed_subscription_notifier is present' do
        let(:failed_subscription_notifier) { double('Notifier', call: nil) }

        it 'uses it' do
          subject
          expect(failed_subscription_notifier).to have_received(:call).with(subscription, original_error)
        end
        it_behaves_like 'does not recover'
      end
    end

    context 'when restart terminator is defined' do
      let(:restart_terminator) { double('Terminator', call: terminator_result) }
      let(:terminator_result) { true }

      before do
        subscription.update(restart_count: 0, max_restarts_number: 1)
      end

      context 'when terminator result is true' do
        it_behaves_like 'does not recover'
      end

      context 'when terminator result is false' do
        let(:terminator_result) { false }

        it_behaves_like 'recover'
      end
    end
  end
end

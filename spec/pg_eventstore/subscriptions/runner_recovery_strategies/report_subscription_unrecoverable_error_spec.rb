# frozen_string_literal: true

RSpec.describe PgEventstore::RunnerRecoveryStrategies::ReportSubscriptionUnrecoverableError do
  let(:instance) { described_class.new(subscription:, failed_subscription_notifier:) }
  let(:subscription) { SubscriptionsHelper.create_with_connection }
  let(:failed_subscription_notifier) { nil }

  it { expect(instance).to be_a(PgEventstore::RunnerRecoveryStrategy) }

  describe '#recovers?' do
    subject { instance.recovers?(error) }

    let(:error) { Class.new(StandardError).new }

    it { is_expected.to eq(true) }
  end

  describe '#recover' do
    subject { instance.recover(error) }

    let(:error) { StandardError.new('something') }

    it 'does not restart the subscription' do
      is_expected.to eq(false)
    end

    context 'when a notifier is given' do
      let(:failed_subscription_notifier) { notifier }
      let(:notifier) { double('Notifier') }

      before do
        allow(notifier).to receive(:call)
      end

      it 'reports the death' do
        subject
        aggregate_failures do
          expect(notifier).to have_received(:call).with(subscription, error)
        end
      end
    end

    context 'when no notifier is configured' do
      it 'does not raise' do
        expect { subject }.not_to raise_error
      end
    end
  end
end

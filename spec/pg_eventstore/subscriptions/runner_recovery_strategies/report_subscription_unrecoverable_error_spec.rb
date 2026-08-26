# frozen_string_literal: true

RSpec.describe PgEventstore::RunnerRecoveryStrategies::ReportUnrecoverableError do
  let(:instance) { described_class.new(subscription:, failed_subscription_notifier:) }
  let(:subscription) { SubscriptionsHelper.create_with_connection }
  let(:failed_subscription_notifier) { nil }

  it { expect(instance).to be_a(PgEventstore::RunnerRecoveryStrategy) }

  describe '#recovers?' do
    subject { instance.recovers?(error) }

    # It is registered last, so matching everything is what makes the death reportable at all.
    context 'when an error is a plain StandardError' do
      let(:error) { StandardError.new }

      it { is_expected.to eq(true) }
    end

    context 'when an error is a WrappedException' do
      let(:error) { PgEventstore::Utils.wrap_exception(StandardError.new) }

      it { is_expected.to eq(true) }
    end
  end

  describe '#recover' do
    subject { instance.recover(error) }

    let(:error) { StandardError.new('something') }

    it 'does not restart the subscription' do
      is_expected.to eq(false)
    end

    context 'when a notifier is given' do
      let(:failed_subscription_notifier) { notifier }
      let(:notifier) { NotifierCollector.new }

      it 'reports the death' do
        subject
        aggregate_failures do
          expect(notifier.calls.size).to eq(1)
          expect(notifier.calls.first[:subscription].id).to eq(subscription.id)
          expect(notifier.calls.first[:error]).to eq(error)
        end
      end

      context 'when the error is wrapped' do
        let(:error) { PgEventstore::Utils.wrap_exception(original_error) }
        let(:original_error) { StandardError.new('original') }

        it 'reports the unwrapped error' do
          subject
          expect(notifier.calls.first[:error]).to eq(original_error)
        end
      end
    end

    context 'when no notifier is configured' do
      it 'does not raise' do
        expect { subject }.not_to raise_error
      end
    end
  end

  # A real collaborator rather than a double, so the arguments the notifier receives are observable.
  class NotifierCollector
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(subscription, error)
      @calls.push({ subscription:, error: })
    end
  end
end

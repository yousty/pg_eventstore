# frozen_string_literal: true

RSpec.describe PgEventstore::RunnerRecoveryStrategies::RestoreSubscriptionFeeder do
  let(:instance) { described_class.new(subscriptions_set_lifecycle: subscriptions_set_lifecycle) }
  let(:subscriptions_set_lifecycle) do
    PgEventstore::SubscriptionsSetLifecycle.new(
      :default, { name: 'Set 1', time_between_restarts: 1, max_restarts_number: 10 }
    )
  end

  it { expect(instance).to be_a(PgEventstore::RunnerRecoveryStrategy) }

  describe '#recovers?' do
    subject { instance.recovers?(StandardError.new) }

    it { is_expected.to eq(true) }
  end

  describe '#recover' do
    subject { instance.recover(StandardError.new) }

    context 'when restarts count is less than max restarts number' do
      it 'sleeps for #time_between_restarts seconds' do
        seconds = PgEventstore::Utils.benchmark { subject }
        expect(seconds).to be_between(1.0, 1.1)
      end
      it { is_expected.to eq(true) }
    end

    context 'when restarts count is greater than or equal to max restarts number' do
      before do
        subscriptions_set_lifecycle.persisted_subscriptions_set.update(max_restarts_number: 1, restart_count: 1)
      end

      it { is_expected.to eq(false) }
      it 'does not sleep' do
        seconds = PgEventstore::Utils.benchmark { subject }
        expect(seconds).to be < 0.1
      end
    end
  end
end

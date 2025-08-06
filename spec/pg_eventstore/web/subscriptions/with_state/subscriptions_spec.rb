# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Subscriptions::WithState::Subscriptions do
  let(:instance) { described_class.new(PgEventstore.connection, current_set, state: state) }
  let(:current_set) { 'FooSet' }
  let(:state) { 'stopped' }

  describe '#subscriptions' do
    subject { instance.subscriptions }

    let!(:subscription1) { SubscriptionsHelper.create(name: 'Sub1', set: 'FooSet', state: 'running') }
    let!(:subscription2) { SubscriptionsHelper.create(name: 'Sub1', set: 'BarSet', state: 'initial') }
    let!(:subscription3) { SubscriptionsHelper.create(name: 'Sub2', set: 'FooSet', state: state) }
    let!(:subscription4) { SubscriptionsHelper.create(name: 'Sub3', set: 'BazSet', state: 'dead') }

    it 'returns all subscriptions by the given set and state' do
      is_expected.to eq([subscription3])
    end
  end
end

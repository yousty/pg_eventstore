# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Subscriptions::WithState::SubscriptionsSet do
  let(:instance) { described_class.new(PgEventstore.connection, current_set, state: state) }
  let(:current_set) { 'FooSet' }
  let(:state) { 'stopped' }

  context '#subscriptions_set' do
    subject { instance.subscriptions_set }

    let!(:set1) { SubscriptionsSetHelper.create(name: 'FooSet') }
    let!(:set2) { SubscriptionsSetHelper.create(name: 'BarSet') }
    let!(:set3) { SubscriptionsSetHelper.create(name: 'FooSet') }
    let!(:set4) { SubscriptionsSetHelper.create(name: 'BazSet') }

    let!(:subscription1) { SubscriptionsHelper.create(locked_by: set1.id, state: 'running', name: 'Sub1') }
    let!(:subscription2) { SubscriptionsHelper.create(locked_by: set3.id, state: state, name: 'Sub2') }

    it 'returns all SubscriptionSet-s by the given set name which have subscriptions with the given state' do
      is_expected.to eq([set3])
    end
  end
end

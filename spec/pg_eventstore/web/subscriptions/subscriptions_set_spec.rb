# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Subscriptions::SubscriptionsSet do
  let(:instance) { described_class.new(PgEventstore.connection, current_set) }
  let(:current_set) { 'FooSet' }

  context '#subscriptions_set' do
    subject { instance.subscriptions_set }

    let!(:set1) { SubscriptionsSetHelper.create(name: 'FooSet') }
    let!(:set2) { SubscriptionsSetHelper.create(name: 'BarSet') }
    let!(:set3) { SubscriptionsSetHelper.create(name: 'FooSet') }
    let!(:set4) { SubscriptionsSetHelper.create(name: 'BazSet') }

    it 'returns all SubscriptionSet-s by the given set name' do
      is_expected.to eq([set1, set3])
    end
  end
end

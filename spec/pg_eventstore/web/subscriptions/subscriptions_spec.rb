# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Subscriptions::Subscriptions do
  let(:instance) { described_class.new(PgEventstore.connection, current_set) }
  let(:current_set) { 'FooSet' }

  context '#subscriptions' do
    subject { instance.subscriptions }

    let!(:subscription1) { SubscriptionsHelper.create(name: 'Sub1', set: 'FooSet') }
    let!(:subscription2) { SubscriptionsHelper.create(name: 'Sub1', set: 'BarSet') }
    let!(:subscription3) { SubscriptionsHelper.create(name: 'Sub2', set: 'FooSet') }
    let!(:subscription4) { SubscriptionsHelper.create(name: 'Sub3', set: 'BazSet') }

    it 'returns all subscriptions by the given set' do
      is_expected.to eq([subscription1, subscription3])
    end
  end
end

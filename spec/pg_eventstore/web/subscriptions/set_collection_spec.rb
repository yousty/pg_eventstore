# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Subscriptions::SetCollection do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#names' do
    subject { instance.names }

    let!(:subscription1) { SubscriptionsHelper.create(name: 'Sub1', set: 'Foo') }
    let!(:subscription2) { SubscriptionsHelper.create(name: 'Sub1', set: 'Bar') }
    let!(:subscriptions_set1) { SubscriptionsSetHelper.create(name: 'Foo') }
    let!(:subscriptions_set2) { SubscriptionsSetHelper.create(name: 'Baz') }

    it 'returns sets names of Subscription-s and SubscriptionsSet-s' do
      is_expected.to eq(['Bar', 'Baz', 'Foo'])
    end
  end
end

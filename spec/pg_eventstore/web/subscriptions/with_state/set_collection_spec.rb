# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Subscriptions::WithState::SetCollection do
  let(:instance) { described_class.new(PgEventstore.connection, state:) }
  let(:state) { 'stopped' }

  describe '#names' do
    subject { instance.names }

    let!(:subscription1) { SubscriptionsHelper.create(name: 'Sub1', set: 'Foo', state:) }
    let!(:subscription2) { SubscriptionsHelper.create(name: 'Sub1', set: 'Bar', state: 'running') }
    let!(:subscription3) { SubscriptionsHelper.create(name: 'Sub1', set: 'Baz', state:) }

    it 'returns sets names of Subscription-s and SubscriptionsSet-s' do
      is_expected.to eq(%w[Baz Foo])
    end
  end
end

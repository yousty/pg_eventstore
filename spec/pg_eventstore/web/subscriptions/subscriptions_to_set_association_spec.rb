# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Subscriptions::SubscriptionsToSetAssociation do
  let(:instance) { described_class.new(subscriptions_set:, subscriptions:) }

  let(:subscriptions_set) { [set1, set2, set3] }
  let(:subscriptions) { [subscription1, subscription2, subscription3] }

  let(:set1) { SubscriptionsSetHelper.create(name: 'FooSet') }
  let(:set2) { SubscriptionsSetHelper.create(name: 'BarSet') }
  let(:set3) { SubscriptionsSetHelper.create(name: 'BazSet') }

  let(:subscription1) { SubscriptionsHelper.create(locked_by: set1.id, set: set1.name, name: 'MySub') }
  let(:subscription2) { SubscriptionsHelper.create(locked_by: set3.id, set: set3.name, name: 'MySub') }
  let(:subscription3) { SubscriptionsHelper.create(set: set2.name, name: 'MySub') }

  describe '#association' do
    subject { instance.association }

    it 'groups subscriptions by corresponding sets' do
      is_expected.to(
        eq(
          set1 => [subscription1],
          set3 => [subscription2],
          PgEventstore::SubscriptionsSet.new => [subscription3],
          set2 => []
        )
      )
    end
  end
end

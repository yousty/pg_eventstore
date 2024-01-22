# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionsManager do
  let(:instance) { described_class.new(config: config, set_name: set_name) }
  let(:config) { PgEventstore.config }
  let(:set_name) { 'Foo' }

  describe '#subscribe' do
    subject { instance.subscribe('MySubscription', handler: proc {}) }

    it 'adds new Subscription' do
      expect { subject }.to change { instance.subscriptions.size }.by(1)
    end
  end
end

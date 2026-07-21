# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionsManager do
  let(:instance) { described_class.new(config:, set_name:) }
  let(:config) { PgEventstore.config }
  let(:set_name) { 'Foo' }

  describe '#subscribe' do
    subject { instance.subscribe('MySubscription', handler: proc {}) }

    it 'adds new Subscription' do
      expect { subject }.to change { instance.subscriptions.size }.by(1)
    end
  end

  describe '#create_replication' do
    subject { instance.create_replication('MyReplica', :replica) }

    context 'when node role is standalone' do
      before do
        PgEventstore.configure do |config|
          config.eventstore_role = PgEventstore::Config::NodeRole::STANDALONE
        end
      end

      it 'raises error' do
        expect { subject }.to raise_error(RuntimeError, /You can't perform this operation/)
      end
    end

    context 'when node role is replica' do
      before do
        PgEventstore.configure do |config|
          config.eventstore_role = PgEventstore::Config::NodeRole::REPLICA
        end
      end

      it 'raises error' do
        expect { subject }.to raise_error(RuntimeError, /You can't perform this operation/)
      end
    end

    context 'when node role is primary' do
      before do
        PgEventstore.configure do |config|
          config.eventstore_role = PgEventstore::Config::NodeRole::PRIMARY
        end
      end

      it 'adds new replica Subscription' do
        expect { subject }.to change { instance.subscriptions.size }.by(1)
      end
    end
  end
end

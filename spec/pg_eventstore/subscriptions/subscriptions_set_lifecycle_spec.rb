# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionsSetLifecycle do
  let(:instance) { PgEventstore::SubscriptionsSetLifecycle.new(:default, subscriptions_set_attrs) }
  let(:subscriptions_set_attrs) { { name: 'Foo', max_restarts_number: 2, time_between_restarts: 3 } }

  describe '#ping_subscriptions_set' do
    subject { instance.ping_subscriptions_set }

    context 'when it is a time to ping' do
      it 'updates SubscriptionsSet#updated_at', timecop: true do
        expect { subject }.to change { instance.persisted_subscriptions_set.reload.updated_at }.to(Time.now.round(6))
      end
    end

    context 'when it is not a time to ping' do
      before do
        instance.ping_subscriptions_set
      end

      it 'does not update SubscriptionsSet#updated_at' do
        expect { subject }.not_to change { instance.persisted_subscriptions_set.reload.updated_at }
      end
    end
  end

  describe '#persisted_subscriptions_set' do
    subject { instance.persisted_subscriptions_set }

    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    it 'creates new one' do
      expect { subject }.to change { queries.find_all(name: subscriptions_set_attrs[:name]).size }.by(1)
    end
    it 'memorizes it' do
      subject
      expect(instance.persisted_subscriptions_set.__id__).to eq(instance.persisted_subscriptions_set.__id__)
    end

    describe 'created PgEventstore::SubscriptionsSet' do
      subject { queries.find!(super().id)  }

      it 'has correct attributes' do
        aggregate_failures do
          expect(subject[:name]).to eq(subscriptions_set_attrs[:name])
          expect(subject[:max_restarts_number]).to eq(subscriptions_set_attrs[:max_restarts_number])
          expect(subject[:time_between_restarts]).to eq(subscriptions_set_attrs[:time_between_restarts])
        end
      end
    end
  end

  describe '#reset_subscriptions_set' do
    subject { instance.reset_subscriptions_set }

    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    context 'when SubscriptionsSet does not exist' do
      it 'does nothing' do
        aggregate_failures do
          expect { subject }.not_to change { instance.subscriptions_set }
          expect(instance.subscriptions_set).to eq(nil)
        end
      end
    end

    context 'when SubscriptionsSet exists' do
      let!(:subscriptions_set) { instance.persisted_subscriptions_set }

      it 'deletes it' do
        expect { subject }.to change { queries.find_all(id: subscriptions_set.id).size }.to(0)
      end
      it 'unassigns it' do
        expect { subject }.to change { instance.subscriptions_set }.to(nil)
      end
    end
  end
end

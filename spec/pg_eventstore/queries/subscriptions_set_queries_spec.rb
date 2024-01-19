# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionsSetQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#find_all' do
    subject { instance.find_all(attrs) }

    let(:attrs) { { name: 'BarCtx' } }

    describe 'when SubscriptionsSets exists' do
      let!(:subscriptions_set_1) { create_subscriptions_set(name: 'BarCtx') }
      let!(:subscriptions_set_2) { create_subscriptions_set(name: 'BarCtx') }

      it 'returns array of their attributes attributes' do
        is_expected.to eq([subscriptions_set_1.options_hash, subscriptions_set_2.options_hash])
      end
    end

    describe 'when SubscriptionsSet does not exist' do
      it { is_expected.to eq([]) }
    end
  end

  describe '#find_by' do
    subject { instance.find_by(attrs) }

    let(:attrs) { { name: 'BarCtx' } }

    describe 'when SubscriptionsSet exists' do
      let!(:subscriptions_set) { create_subscriptions_set(name: 'BarCtx') }

      it 'returns its attributes' do
        is_expected.to eq(subscriptions_set.options_hash)
      end
    end

    describe 'when SubscriptionsSet does not exist' do
      it { is_expected.to be_nil }
    end
  end

  describe '#find!' do
    subject { instance.find!(id) }

    let(:id) { SecureRandom.uuid }

    describe 'when SubscriptionsSet exists' do
      let(:id) { subscriptions_set.id }
      let!(:subscriptions_set) { PgEventstore::SubscriptionsSet.new(**instance.create(name: 'Foo')) }

      it 'returns its attributes' do
        is_expected.to eq(subscriptions_set.options_hash)
      end
    end

    describe 'when SubscriptionsSet does not exist' do
      it 'raises error' do
        expect { subject }.to(
          raise_error(
            PgEventstore::RecordNotFound, "Could not find/update \"subscriptions_set\" record with #{id.inspect} id."
          )
        )
      end
    end
  end

  describe '#create' do
    subject { instance.create(attrs) }

    let(:attrs) { { name: 'FooCtx' } }

    context 'when SubscriptionsSet with the given name already exists' do
      let!(:subscriptions_set) { create_subscriptions_set(name: 'FooCtx') }

      it 'creates another one' do
        expect { subject }.to change { instance.find_all(attrs).size }.by(1)
      end
      it 'returns its attributes' do
        aggregate_failures do
          is_expected.to be_a(Hash)
          expect(subject[:id]).to match(EventHelpers::UUID_REGEXP)
          expect(subject[:id]).not_to eq(subscriptions_set.id)
          expect(subject[:name]).to eq('FooCtx')
        end
      end
    end

    context 'when SubscriptionsSet does not exist' do
      it 'creates another one' do
        expect { subject }.to change { instance.find_all(attrs).size }.by(1)
      end
      it 'returns its attributes' do
        aggregate_failures do
          is_expected.to be_a(Hash)
          expect(subject[:id]).to match(EventHelpers::UUID_REGEXP)
          expect(subject[:name]).to eq('FooCtx')
        end
      end
    end
  end

  describe '#update' do
    subject { instance.update(id, attrs) }

    let(:id) { subscriptions_set.id }
    let(:subscriptions_set) { create_subscriptions_set }
    let(:attrs) { { state: 'running' } }

    context 'when SubscriptionsSet exists' do
      it 'updates the given attribute' do
        expect { subject }.to change { instance.find_by(id: id)[:state] }.to('running')
      end
      it 'updates updated_at column' do
        expect { subject }.to change { instance.find_by(id: id)[:updated_at] }
      end
      it 'returns updated attributes' do
        is_expected.to match(a_hash_including(id: id, state: 'running'))
      end

      context 'when SubscriptionsSet is updated by someone else' do
        before do
          instance.update(id, { name: 'BazCtx' })
        end

        it 'returns those changes as well' do
          is_expected.to match(a_hash_including(id: id, state: 'running', name: 'BazCtx'))
        end
      end
    end

    context 'when SubscriptionsSet does not exist' do
      let(:subscriptions_set) { PgEventstore::SubscriptionsSet.new(id: SecureRandom.uuid) }

      it 'raises error' do
        expect { subject }.to(
          raise_error(
            PgEventstore::RecordNotFound,
            "Could not find/update \"subscriptions_set\" record with #{subscriptions_set.id.inspect} id."
          )
        )
      end
    end
  end

  describe '#delete' do
    subject { instance.delete(id) }

    let(:id) { SecureRandom.uuid }

    context 'when SubscriptionsSet exists' do
      let(:id) { subscriptions_set.id }
      let!(:subscriptions_set) { create_subscriptions_set }

      it 'deletes it' do
        expect { subject }.to change { instance.find_by(id: subscriptions_set.id) }.to(nil)
      end
    end

    context 'when SubscriptionsSet does not exist' do
      it 'does not thing' do
        expect { subject }.not_to raise_error
      end
    end
  end
end

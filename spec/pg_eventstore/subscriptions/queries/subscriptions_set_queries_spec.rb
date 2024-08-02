# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionsSetQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

  describe '#find_all' do
    subject { instance.find_all(attrs) }

    let(:attrs) { { name: 'BarCtx' } }

    describe 'when SubscriptionsSets exists' do
      let!(:subscriptions_set_1) { SubscriptionsSetHelper.create(name: 'BarCtx') }
      let!(:subscriptions_set_2) { SubscriptionsSetHelper.create(name: 'BarCtx') }

      it 'returns array of their attributes attributes' do
        is_expected.to eq([subscriptions_set_1.options_hash, subscriptions_set_2.options_hash])
      end
    end

    describe 'when SubscriptionsSet does not exist' do
      it { is_expected.to eq([]) }
    end
  end

  describe '#find_all_by_subscription_state' do
    subject { instance.find_all_by_subscription_state(name: name, state: state) }

    let(:name) { 'BarCtx' }
    let(:state) { 'running' }

    let!(:subscriptions_set1) { SubscriptionsSetHelper.create(name: name) }

    context 'when SubscriptionsSet with the given name does not have subscriptions' do
      it { is_expected.to eq([]) }
    end

    context 'when SubscriptionsSet with the given name have subscriptions with another state' do
      let!(:subscription1) do
        SubscriptionsHelper.create(locked_by: subscriptions_set1.id, state: 'stopped', name: 'Sub1')
      end
      let!(:subscription2) { SubscriptionsHelper.create(locked_by: subscriptions_set1.id, state: 'dead', name: 'Sub2') }

      it { is_expected.to eq([]) }
    end

    context 'when SubscriptionsSet with the given name have subscriptions with the given state' do
      let!(:subscription1) { SubscriptionsHelper.create(locked_by: subscriptions_set1.id, state: state, name: 'Sub1') }
      let!(:subscription2) { SubscriptionsHelper.create(locked_by: subscriptions_set1.id, state: state, name: 'Sub2') }

      it { is_expected.to eq([subscriptions_set1.options_hash]) }
    end

    context 'when another SubscriptionsSet with the same name with suitable subscriptions exists' do
      let!(:subscriptions_set2) { SubscriptionsSetHelper.create(name: name) }

      let!(:subscription1) { SubscriptionsHelper.create(locked_by: subscriptions_set1.id, state: state, name: 'Sub1') }
      let!(:subscription2) { SubscriptionsHelper.create(locked_by: subscriptions_set1.id, state: state, name: 'Sub2') }
      let!(:subscription3) { SubscriptionsHelper.create(locked_by: subscriptions_set2.id, state: state, name: 'Sub3') }

      it { is_expected.to match_array([subscriptions_set1.options_hash, subscriptions_set2.options_hash]) }
    end
  end

  describe '#set_names' do
    subject { instance.set_names }

    let!(:subscriptions_set_1) { SubscriptionsSetHelper.create(name: 'FooCtx') }
    let!(:subscriptions_set_2) { SubscriptionsSetHelper.create(name: 'BarCtx') }
    let!(:subscriptions_set_3) { SubscriptionsSetHelper.create(name: 'BarCtx') }

    it 'returns names of all sets' do
      is_expected.to eq(['BarCtx', 'FooCtx'])
    end
  end

  describe '#find_by' do
    subject { instance.find_by(attrs) }

    let(:attrs) { { name: 'BarCtx' } }

    describe 'when SubscriptionsSet exists' do
      let!(:subscriptions_set) { SubscriptionsSetHelper.create(name: 'BarCtx') }

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

    let(:id) { 1 }

    describe 'when SubscriptionsSet exists' do
      let(:id) { subscriptions_set.id }
      let!(:subscriptions_set) { SubscriptionsSetHelper.create(name: 'Foo') }

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
      let!(:subscriptions_set) { SubscriptionsSetHelper.create(name: 'FooCtx') }

      it 'creates another one' do
        expect { subject }.to change { instance.find_all(attrs).size }.by(1)
      end
      it 'returns its attributes' do
        aggregate_failures do
          is_expected.to be_a(Hash)
          expect(subject[:id]).to be_an(Integer)
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
          expect(subject[:id]).to be_an(Integer)
          expect(subject[:name]).to eq('FooCtx')
        end
      end
    end
  end

  describe '#update' do
    subject { instance.update(id, attrs) }

    let(:id) { subscriptions_set.id }
    let(:subscriptions_set) { SubscriptionsSetHelper.create }
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
      let(:subscriptions_set) { PgEventstore::SubscriptionsSet.new(id: 1) }

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

    let(:id) { 1 }

    context 'when SubscriptionsSet exists' do
      let(:id) { subscriptions_set.id }
      let!(:subscriptions_set) { SubscriptionsSetHelper.create }

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

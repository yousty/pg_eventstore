# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionsSet do
  it { is_expected.to be_a(PgEventstore::Extensions::UsingConnectionExtension) }
  it { is_expected.to be_a(PgEventstore::Extensions::OptionsExtension) }

  describe 'attributes' do
    it { is_expected.to have_attribute(:id) }
    it { is_expected.to have_attribute(:name) }
    it { is_expected.to have_attribute(:state) }
    it { is_expected.to have_attribute(:restart_count) }
    it { is_expected.to have_attribute(:max_restarts_number) }
    it { is_expected.to have_attribute(:time_between_restarts) }
    it { is_expected.to have_attribute(:last_restarted_at) }
    it { is_expected.to have_attribute(:last_error) }
    it { is_expected.to have_attribute(:last_error_occurred_at) }
    it { is_expected.to have_attribute(:created_at) }
    it { is_expected.to have_attribute(:updated_at) }
  end

  describe '#assign_attributes' do
    subject { subscriptions_set.assign_attributes(attrs) }

    let(:subscriptions_set) { described_class.new }
    let(:attrs) { { id: 1, state: 'running' } }

    it 'assigns the given attributes' do
      expect { subject }.to change { subscriptions_set.options_hash }.to(include(attrs))
    end
    it 'returns the given attributes' do
      is_expected.to eq(attrs)
    end
  end

  describe '#update' do
    subject { subscriptions_set.update(attrs) }

    let(:subscriptions_set) do
      described_class.using_connection(:default).new(**queries.create(name: 'Foo'))
    end
    let(:attrs) { { state: 'stopped', name: 'Bar' } }
    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    it 'updates attributes of the given SubscriptionsSet' do
      expect { subject }.to change { subscriptions_set.reload.options_hash }.to(include(attrs))
    end
    it 'assigns those attributes after update' do
      subject
      aggregate_failures do
        expect(subscriptions_set.state).to eq(attrs[:state])
        expect(subscriptions_set.name).to eq(attrs[:name])
      end
    end
    it 'returns updated attributes' do
      is_expected.to include(attrs)
    end
  end

  describe '#delete' do
    subject { subscriptions_set.delete }

    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }
    let!(:subscriptions_set) do
      described_class.using_connection(:default).new(**queries.create(name: 'Foo'))
    end

    context 'when SubscriptionsSet exists' do
      it 'deletes it' do
        expect { subject }.to change { queries.find_all(name: 'Foo').size }.by(-1)
      end
    end

    context 'when SubscriptionsSet does not exist' do
      let(:subscriptions_set) { described_class.using_connection(:default).new(id: 1) }

      it 'does nothing' do
        expect { subject }.not_to raise_error
      end
    end
  end

  describe '#dup' do
    subject { subscriptions_set.dup }

    let(:subscriptions_set) do
      described_class.new(
        **queries.create(
          name: 'Foo',
          last_error: { 'class' => 'StandardError', 'message' => 'Oops', 'backtrace' => ['1.rb'] }
        )
      )
    end
    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    it 'returns the copy of the given SubscriptionsSet' do
      aggregate_failures do
        is_expected.to be_a(described_class)
        expect(subject.options_hash).to eq(subscriptions_set.options_hash)
        expect(subject.__id__).not_to eq(subscriptions_set.__id__)
      end
    end
    it 'does not duplicate the associated connection' do
      expect { subject.update(state: 'stopped') }.to raise_error(/No connection was set/)
    end
    it 'duplicates complex objects properly' do
      expect { subject.last_error['backtrace'][0][0] = '' }.not_to change { subscriptions_set.last_error }
    end
  end

  describe '#reload' do
    subject { subscriptions_set.reload }

    let(:subscriptions_set) do
      described_class.using_connection(:default).new(**queries.create(name: 'Foo'))
    end
    let(:queries) { PgEventstore::SubscriptionsSetQueries.new(PgEventstore.connection) }

    before do
      queries.update(subscriptions_set.id, { name: 'Bar' })
    end

    it 'loads new record state from database' do
      expect { subject }.to change { subscriptions_set.name }.to('Bar')
    end
    it { is_expected.to eq(subscriptions_set) }
  end

  describe '#==' do
    subject { set1 == set2 }

    let(:set1) { described_class.new(id: 1) }
    let(:set2) { described_class.new(id: 1) }

    context 'when ids matches' do
      it { is_expected.to eq(true) }
    end

    context 'when ids does not match' do
      let(:set2) { described_class.new(id: 2) }

      it { is_expected.to eq(false) }
    end

    context 'when set2 is not a SubscriptionsSet object' do
      let(:set2) { Object.new }

      it { is_expected.to eq(false) }
    end
  end

  describe '#hash' do
    let(:hash) { {} }
    let(:set1) { described_class.new(id: 1) }
    let(:set2) { described_class.new(id: 1) }

    before do
      hash[set1] = :foo
    end

    context 'when sets are equal' do
      it 'recognizes second set' do
        expect(hash[set2]).to eq(:foo)
      end
    end

    context 'when sets differ' do
      let(:set2) { described_class.new(id: 2) }

      it 'does not recognize second set' do
        expect(hash[set2]).to eq(nil)
      end
    end
  end
end

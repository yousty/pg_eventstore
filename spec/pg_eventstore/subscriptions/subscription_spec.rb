# frozen_string_literal: true

RSpec.describe PgEventstore::Subscription do
  it { is_expected.to be_a(PgEventstore::Extensions::UsingConnectionExtension) }
  it { is_expected.to be_a(PgEventstore::Extensions::OptionsExtension) }

  describe 'attributes' do
    it { is_expected.to have_attribute(:id) }
    it { is_expected.to have_attribute(:set) }
    it { is_expected.to have_attribute(:name) }
    it { is_expected.to have_attribute(:total_processed_events) }
    it { is_expected.to have_attribute(:options) }
    it { is_expected.to have_attribute(:current_position) }
    it { is_expected.to have_attribute(:state) }
    it { is_expected.to have_attribute(:average_event_processing_time) }
    it { is_expected.to have_attribute(:restart_count) }
    it { is_expected.to have_attribute(:max_restarts_number) }
    it { is_expected.to have_attribute(:time_between_restarts) }
    it { is_expected.to have_attribute(:last_restarted_at) }
    it { is_expected.to have_attribute(:last_error) }
    it { is_expected.to have_attribute(:last_error_occurred_at) }
    it { is_expected.to have_attribute(:chunk_query_interval) }
    it { is_expected.to have_attribute(:last_chunk_fed_at) }
    it { is_expected.to have_attribute(:last_chunk_greatest_position) }
    it { is_expected.to have_attribute(:locked_by) }
    it { is_expected.to have_attribute(:created_at) }
    it { is_expected.to have_attribute(:updated_at) }
  end

  describe '#options=' do
    subject { subscription.options = value }

    let(:subscription) { described_class.new }

    let(:value) { { 'filter' => { 'streams' => [{ 'context' => 'FooCtx' }] } } }

    it 'symbolizes all nested keys recursively' do
      expect { subject }.to change { subscription.options }.to(filter: { streams: [{ context: 'FooCtx' }] })
    end
  end

  describe '#update' do
    subject { subscription.update(attrs) }

    let(:subscription) { SubscriptionsHelper.create_with_connection }
    let(:attrs) do
      { locked_by: SecureRandom.uuid, restart_count: 321, max_restarts_number: 123, time_between_restarts: 10 }
    end

    it 'updates attributes of the given subscription' do
      expect { subject }.to change { subscription.reload.options_hash }.to(include(attrs))
    end
    it 'assigns those attributes after update' do
      subject
      aggregate_failures do
        expect(subscription.locked_by).to eq(attrs[:locked_by])
        expect(subscription.restart_count).to eq(attrs[:restart_count])
        expect(subscription.max_restarts_number).to eq(attrs[:max_restarts_number])
        expect(subscription.time_between_restarts).to eq(attrs[:time_between_restarts])
      end
    end
    it 'returns updated attributes' do
      is_expected.to include(attrs)
    end
  end

  describe '#assign_attributes' do
    subject { subscription.assign_attributes(attrs) }

    let(:subscription) { described_class.new }
    let(:attrs) { { id: 1, state: 'running' } }

    it 'assigns the given attributes' do
      expect { subject }.to change { subscription.options_hash }.to(include(attrs))
    end
    it 'returns the given attributes' do
      is_expected.to eq(attrs)
    end
  end

  describe '#lock!' do
    subject { subscription.lock!(lock_id) }

    let(:subscription) do
      PgEventstore::Subscription.using_connection(:default).
        new(
          set: set, name: name, options: { resolve_link_tos: true }, max_restarts_number: 12, chunk_query_interval: 34,
          time_between_restarts: 1
        )
    end
    let(:set) { 'FooSet' }
    let(:name) { 'MySubscription1' }
    let(:lock_id) { SecureRandom.uuid }
    let(:queries) { PgEventstore::SubscriptionQueries.new(PgEventstore.connection) }

    context 'when Subscription does not exist' do
      it 'creates it' do
        expect { subject }.to change { queries.find_by(set: set, name: name) }.to(instance_of(Hash))
      end
      it 'assigns persisted attributes' do
        subject
        expect(subscription.options_hash).to(
          eq(PgEventstore::Subscription.new(**queries.find_by(set: set, name: name)).options_hash)
        )
      end
      it { is_expected.to eq(subscription) }

      describe 'created Subscription' do
        subject { super(); PgEventstore::Subscription.new(**queries.find_by(set: set, name: name)) }

        it 'has correct attributes' do
          aggregate_failures do
            expect(subject.id).to be_a(Integer)
            expect(subject.set).to eq(set)
            expect(subject.name).to eq(name)
            expect(subject.total_processed_events).to eq(0)
            expect(subject.options).to eq(resolve_link_tos: true)
            expect(subject.current_position).to eq(nil)
            expect(subject.state).to eq('initial')
            expect(subject.average_event_processing_time).to eq(nil)
            expect(subject.restart_count).to eq(0)
            expect(subject.max_restarts_number).to eq(12)
            expect(subject.last_restarted_at).to eq(nil)
            expect(subject.last_error).to eq(nil)
            expect(subject.last_error_occurred_at).to eq(nil)
            expect(subject.chunk_query_interval).to eq(34)
            expect(subject.last_chunk_fed_at).to eq(Time.at(0).utc)
            expect(subject.last_chunk_greatest_position).to eq(nil)
            expect(subject.locked_by).to eq(lock_id)
            expect(subject.created_at).to be_between(Time.now.utc - 1, Time.now.utc + 1)
            expect(subject.updated_at).to be_between(Time.now.utc - 1, Time.now.utc + 1)
          end
        end
      end
    end

    context 'when subscription exists' do
      let!(:existing_subscription) do
        SubscriptionsHelper.create_with_connection(
          set: set,
          name: name,
          options: { resolve_link_tos: false },
          max_restarts_number: 21,
          chunk_query_interval: 43,
          restart_count: 10,
          last_restarted_at: Time.now.utc,
          last_chunk_fed_at: Time.now.utc,
          last_chunk_greatest_position: 1234,
          state: 'stopped'
        )
      end

      shared_examples 'updating of the subscription' do
        it 'updates it' do
          expect { subject }.to change {
            existing_subscription.reload.options_hash
          }.to(
            include(
              options: { resolve_link_tos: true },
              max_restarts_number: 12,
              chunk_query_interval: 34,
              restart_count: 0,
              last_restarted_at: nil,
              last_chunk_fed_at: Time.at(0).utc,
              last_chunk_greatest_position: nil,
              state: 'initial',
              locked_by: lock_id
            )
          )
        end
        it 'assigns updated attributes' do
          subject
          expect(subscription.options_hash).to eq(existing_subscription.reload.options_hash)
        end
        it { is_expected.to eq(subscription) }
      end

      context 'when it is not locked' do
        it_behaves_like 'updating of the subscription'
      end

      context 'when it is locked' do
        before do
          queries.update(existing_subscription.id, locked_by: SecureRandom.uuid)
        end

        it 'raises error' do
          expect { subject }.to raise_error(PgEventstore::SubscriptionAlreadyLockedError)
        end

        context 'when "force" flag is true' do
          subject { subscription.lock!(lock_id, true) }

          it_behaves_like 'updating of the subscription'
        end
      end
    end
  end

  describe '#unlock!' do
    subject { subscription.unlock! }

    let(:subscription) { SubscriptionsHelper.create_with_connection }

    context 'when subscription is not locked' do
      it 'does not change it' do
        expect { subject }.not_to change { subscription.reload.options_hash }
      end
    end

    context 'when subscription is locked' do
      before do
        subscription.update(locked_by: SecureRandom.uuid)
      end

      it 'unlocks it' do
        expect { subject }.to change { subscription.reload.locked_by }.to(nil)
      end
    end

    context 'when subscription is locked, by someone else' do
      let(:queries) { PgEventstore::SubscriptionQueries.new(PgEventstore.connection) }

      before do
        queries.update(subscription.id, { locked_by: SecureRandom.uuid })
      end

      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::SubscriptionUnlockError)
      end
    end
  end

  describe '#dup' do
    subject { subscription.dup }

    let(:subscription) { SubscriptionsHelper.create_with_connection(options: { filter: { event_types: ['Foo'] } }) }

    it 'returns the copy of the given subscription' do
      aggregate_failures do
        is_expected.to be_a(PgEventstore::Subscription)
        expect(subject.options_hash).to eq(subscription.options_hash)
        expect(subject.__id__).not_to eq(subscription.__id__)
      end
    end
    it 'does not duplicate the associated connection' do
      expect { subject.update(state: 'stopped') }.to raise_error(/No connection was set/)
    end
    it 'duplicates complex objects properly' do
      expect { subject.options[:filter][:event_types][0][0] = 'f' }.not_to change { subscription.options }
    end
  end

  describe '#reload' do
    subject { subscription.reload }

    let(:subscription) { SubscriptionsHelper.create_with_connection }
    let(:queries) { PgEventstore::SubscriptionQueries.new(PgEventstore.connection) }

    before do
      queries.update(subscription.id, { options: { resolve_link_tos: true } })
    end

    it 'loads new record state from database' do
      expect { subject }.to change { subscription.options }.to(resolve_link_tos: true)
    end
    it { is_expected.to eq(subscription) }
  end
end

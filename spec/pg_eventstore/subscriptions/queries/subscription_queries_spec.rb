# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionQueries do
  let(:instance) { described_class.new(PgEventstore.connection, query_strategy) }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }

  describe '#find_by' do
    subject { instance.find_by(attrs) }

    let(:attrs) { { set: 'Foo', name: 'Bar' } }

    describe 'when subscription exists' do
      let!(:subscription) { SubscriptionsHelper.create(**attrs) }

      it 'returns its attributes' do
        is_expected.to eq(subscription.options_hash)
      end
    end

    describe 'when subscription does not exist' do
      it { is_expected.to be_nil }
    end
  end

  describe '#find_all' do
    subject { instance.find_all(attrs) }

    let(:attrs) { { set: 'FooSet' } }

    context 'when there are matching subscriptions' do
      let!(:subscription1) { SubscriptionsHelper.create(set: 'FooSet', name: 'Foo') }
      let!(:subscription2) { SubscriptionsHelper.create(set: 'BarSet', name: 'Bar') }
      let!(:subscription3) { SubscriptionsHelper.create(set: 'FooSet', name: 'Baz') }

      it 'returns them' do
        is_expected.to eq([subscription1.options_hash, subscription3.options_hash])
      end
    end

    context 'when there are no matching subscriptions' do
      it { is_expected.to eq([]) }
    end
  end

  describe '#set_collection' do
    subject { instance.set_collection }

    let!(:subscription1) { SubscriptionsHelper.create(set: 'FooSet', name: 'Foo', state: 'running') }
    let!(:subscription2) { SubscriptionsHelper.create(set: 'BarSet', name: 'Bar', state: 'stopped') }
    let!(:subscription3) { SubscriptionsHelper.create(set: 'FooSet', name: 'Baz', state: 'dead') }

    it 'returns all set names' do
      is_expected.to eq(%w[BarSet FooSet])
    end

    context 'when state is provided' do
      subject { instance.set_collection('stopped') }

      it 'returns set names of subscriptions with the given state' do
        is_expected.to eq(['BarSet'])
      end
    end
  end

  describe '#find!' do
    subject { instance.find!(id) }

    let(:id) { 123 }

    describe 'when subscription exists' do
      let(:id) { subscription.id }
      let!(:subscription) { SubscriptionsHelper.create }

      it 'returns its attributes' do
        is_expected.to eq(subscription.options_hash)
      end
    end

    describe 'when subscription does not exist' do
      it 'raises error' do
        expect { subject }.to(
          raise_error(PgEventstore::RecordNotFound, 'Could not find/update/delete "subscriptions" record by 123.')
        )
      end
    end
  end

  describe '#create' do
    subject { instance.create(attrs) }

    let(:attrs) { { set: 'Foo', name: 'Bar' } }

    describe 'when subscription with same set and name exists' do
      let!(:subscription) { SubscriptionsHelper.create(**attrs) }

      it 'raises error' do
        expect { subject }.to raise_error(PG::UniqueViolation)
      end
    end

    describe 'when subscription does not exist' do
      it 'creates it' do
        expect { subject }.to change { instance.find_by(attrs) }.to(instance_of(Hash))
      end
      it 'has correct attributes' do
        aggregate_failures do
          expect(subject[:id]).to be_a(Integer)
          expect(subject[:set]).to eq('Foo')
          expect(subject[:name]).to eq('Bar')
        end
      end
    end
  end

  describe '#update' do
    subject { instance.update(id, attrs:, locked_by: subscriptions_set.id) }

    let(:id) { subscription.id }
    let(:subscription) { SubscriptionsHelper.create(locked_by: subscriptions_set.id) }
    let(:subscriptions_set) { SubscriptionsSetHelper.create }
    let(:attrs) { { max_restarts_number: 123 } }

    context 'when subscription exists' do
      it 'updates the given attribute' do
        expect { subject }.to change { instance.find_by(id:)[:max_restarts_number] }.to(123)
      end
      it 'updates updated_at column' do
        expect { subject }.to change { instance.find_by(id:)[:updated_at] }
      end
      it 'returns updated attributes', :timecop do
        is_expected.to eq(attrs.merge(updated_at: Time.now.round(6)))
      end

      context 'when subscription is updated by someone else' do
        before do
          instance.update(id, attrs: { restart_count: 2 }, locked_by: subscriptions_set.id)
        end

        it 'does not return those changes' do
          is_expected.not_to include(:restart_count)
        end
      end

      context 'when subscription is force-locked by another SubscriptionsSet' do
        let(:another_subscriptions_set) { SubscriptionsSetHelper.create(name: 'BarSet') }

        before do
          instance.lock!(subscription.id, another_subscriptions_set.id, force: true)
        end

        it 'raises error' do
          expect { subject }.to raise_error(PgEventstore::WrongLockIdError, /Could not update subscription/)
        end
      end
    end

    context 'when subscription does not exist' do
      let(:subscription) { PgEventstore::Subscription.new(id: -1) }

      it 'raises error' do
        expect { subject }.to(
          raise_error(PgEventstore::RecordNotFound, 'Could not find/update/delete "subscriptions" record by -1.')
        )
      end
    end
  end

  describe '#create_or_replace_view' do
    describe 'creating and replacing a view' do
      subject { instance.create_or_replace_view(subscription.id, options, subscriptions_set.id) }

      let(:subscription) { SubscriptionsHelper.create }
      let(:subscriptions_set) { SubscriptionsSetHelper.create }
      let(:options) { {} }

      before do
        instance.lock!(subscription.id, subscriptions_set.id, force: false)
      end

      context 'when view does not exist' do
        it 'creates sql view for the given subscription' do
          expect { subject }.to change {
            query_strategy.exec(<<~SQL).to_a
              select table_name from information_schema.views where table_name like 'subscription_%'
            SQL
          }.from([]).to([{ 'table_name' => "subscription_#{subscription.id}" }])
        end
      end

      context 'when view already exists' do
        before do
          instance.create_or_replace_view(
            subscription.id,
            { filter: { event_types: ['Foo'] } }, subscriptions_set.id
          )
        end

        it 're-creates it' do
          view_name = "subscription_#{subscription.id}"
          expect { subject }.to change {
            query_strategy.exec_params(<<~SQL, [view_name]).to_a.first&.[]('view_definition')
              select view_definition from information_schema.views where table_name = $1
            SQL
          }.from(a_string_including('Foo'))
        end
      end
    end

    describe 'filtering using created sql view' do
      subject do
        query_strategy.exec("select * from #{view_name}").map do |attrs|
          PgEventstore::EventGlobalIndex::SubscriptionRepr.new(**attrs.transform_keys(&:to_sym))
        end
      end

      let(:subscription) { SubscriptionsHelper.create }
      let(:subscriptions_set) { SubscriptionsSetHelper.create }
      let(:view_name) { "subscription_#{subscription.id}" }
      let(:options) { {} }

      let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }
      let(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '2') }
      let(:stream4) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Baz', stream_id: '1') }

      let(:event1) do
        event = PgEventstore::Event.new(type: 'Foo')
        PgEventstore.client.append_to_stream(stream1, event)
      end
      let(:event2) do
        event = PgEventstore::Event.new(type: 'Foo')
        PgEventstore.client.append_to_stream(stream2, event)
      end
      let(:event3) do
        event = PgEventstore::Event.new(type: 'Baz')
        PgEventstore.client.append_to_stream(stream3, event)
      end
      let(:event4) do
        event = PgEventstore::Event.new(type: 'Bar')
        PgEventstore.client.append_to_stream(stream4, event)
      end
      let(:event5) do
        event = PgEventstore::Event.new(type: 'Bar')
        PgEventstore.client.append_to_stream(stream4, event)
      end

      let(:indexes) { prepare_subscription_indexes([event1, event2, event3, event4, event5]) }
      let(:event_idx1) { indexes[0] }
      let(:event_idx2) { indexes[1] }
      let(:event_idx3) { indexes[2] }
      let(:event_idx4) { indexes[3] }
      let(:event_idx5) { indexes[4] }

      before do
        instance.lock!(subscription.id, subscriptions_set.id, force: false)
        instance.create_or_replace_view(subscription.id, options, subscriptions_set.id)
        event1
        event2
        event3
        event4
        event5
        PgEventstore::SubscriptionServiceQueries.new(PgEventstore.connection).assign_subscription_position
      end

      context 'when filters are empty' do
        it 'returns all indexes' do
          is_expected.to eq([event_idx1, event_idx2, event_idx3, event_idx4, event_idx5])
        end
      end

      context 'when event_types: filter is given' do
        describe 'filtering by string' do
          let(:options) { { filter: { event_types: ['Foo'] } } }

          it 'filters indexes by the given type' do
            is_expected.to eq([event_idx1, event_idx2])
          end
        end

        describe 'filtering by prefix' do
          let(:options) { { filter: { event_types: [{ prefix: 'Ba' }] } } }

          it 'filters indexes by the given prefix' do
            is_expected.to eq([event_idx3, event_idx4, event_idx5])
          end
        end
      end

      context 'when :streams filter is given' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }] } } }

        describe 'filtering by :context' do
          it 'returns indexes of given context' do
            is_expected.to eq([event_idx1])
          end
        end

        describe 'filtering by :context and :stream_name' do
          let(:options) { { filter: { streams: [{ context: 'BarCtx', stream_name: 'Bar' }] } } }

          it 'returns indexes of given context and stream name' do
            is_expected.to eq([event_idx2, event_idx3])
          end
        end

        describe 'filtering by stream' do
          let(:options) { { filter: { streams: [stream3.to_hash] } } }

          it 'returns indexes of given context and stream name' do
            is_expected.to eq([event_idx3])
          end
        end

        describe 'filtering by multiple streams filters' do
          let(:options) { { filter: { streams: [{ context: 'FooCtx' }, { context: 'BarCtx', stream_name: 'Baz' }] } } }

          it 'returns indexes from intersection of given streams filters' do
            is_expected.to eq([event_idx1, event_idx4, event_idx5])
          end
        end

        context 'when overlapping streams filter is given' do
          let(:options) do
            {
              filter: {
                streams: [
                  { context: 'BarCtx' },
                  { context: 'BarCtx', stream_name: 'Bar' },
                  { context: 'BarCtx', stream_name: 'Baz', stream_id: '1' },
                ]
              }
            }
          end

          it 'returns indexes for the most common filter' do
            is_expected.to eq([event_idx2, event_idx3, event_idx4, event_idx5])
          end
        end
      end

      describe 'combining :streams and :event_types filters' do
        let(:options) do
          {
            filter: {
              streams: [{ context: 'BarCtx' }],
              event_types: %w[Foo Bar],
            }
          }
        end

        it 'returns indexes by the given streams and event types filters' do
          is_expected.to eq([event_idx2, event_idx4, event_idx5])
        end
      end
    end
  end

  describe '#lock!' do
    subject { instance.lock!(id, lock_id) }

    let(:lock_id) { SubscriptionsSetHelper.create.id }
    let(:id) { 123 }

    shared_examples 'fails to lock' do
      it 'raises error' do
        expect { subject }.to(
          raise_error(
            PgEventstore::SubscriptionAlreadyLockedError,
            <<~TEXT.strip
              Could not lock subscription from #{subscription.set.inspect} set with #{subscription.name.inspect} \
              name. It is already locked by ##{subscriptions_set_id.inspect} set.
            TEXT
          )
        )
      end
    end

    context 'when subscription exists' do
      let(:subscription) { SubscriptionsHelper.create_with_connection }
      let(:id) { subscription.id }

      context 'when subscription is not locked' do
        it 'locks it' do
          expect { subject }.to change { instance.find!(id)[:locked_by] }.to(lock_id)
        end
        it 'returns the given lock id' do
          is_expected.to eq(lock_id)
        end
      end

      context 'when subscription is locked by the given SubscriptionsSet' do
        before do
          instance.update(id, attrs: { locked_by: lock_id }, locked_by: lock_id)
        end

        it_behaves_like 'fails to lock' do
          let(:subscriptions_set_id) { lock_id }
        end
      end

      context 'when subscription is locked by another SubscriptionsSet' do
        let(:another_subscriptions_set) { SubscriptionsSetHelper.create(name: 'BarSet') }

        before do
          instance.update(
            id, attrs: { locked_by: another_subscriptions_set.id }, locked_by: another_subscriptions_set.id
          )
        end

        it_behaves_like 'fails to lock' do
          let(:subscriptions_set_id) { another_subscriptions_set.id }
        end
      end
    end

    context 'when subscription does not exist' do
      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::RecordNotFound)
      end
    end
  end

  describe '#delete' do
    subject { instance.delete(subscription.id) }

    let(:subscription) { SubscriptionsHelper.create }

    it 'deletes the given subscriptions' do
      expect { subject }.to change { instance.find_by(id: subscription.id) }.to(nil)
    end
  end

  describe '#ping_all' do
    subject { instance.ping_all(subscriptions_set1.id, [subscription1.id, subscription2.id]) }

    let(:subscriptions_set1) { SubscriptionsSetHelper.create(name: 'Set1') }
    let(:subscriptions_set2) { SubscriptionsSetHelper.create(name: 'Set2') }

    let!(:subscription1) do
      SubscriptionsHelper.create_with_connection(name: 'sub1', locked_by: subscriptions_set1.id)
    end
    let!(:subscription2) do
      SubscriptionsHelper.create_with_connection(name: 'sub2', locked_by: subscriptions_set2.id)
    end
    let!(:subscription3) do
      SubscriptionsHelper.create_with_connection(name: 'sub3', locked_by: subscriptions_set1.id)
    end

    it 'updates #updated_at of the given Subscription, locked by the given SubscriptionsSet' do
      expect { subject }.to change { subscription1.reload.updated_at }
    end
    it 'does not update #updated_at of the Subscription, locked by another SubscriptionsSet' do
      expect { subject }.not_to change { subscription2.reload.updated_at }
    end
    it 'does not update #updated_at of another Subscription from the same SubscriptionsSet' do
      expect { subject }.not_to change { subscription3.reload.updated_at }
    end
    it 'returns id/Time association', :timecop do
      is_expected.to eq(subscription1.id => Time.now.utc.round(6))
    end
  end
end

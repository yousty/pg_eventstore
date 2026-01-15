# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionQueries do
  let(:instance) { described_class.new(PgEventstore.connection) }

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
          raise_error(PgEventstore::RecordNotFound, 'Could not find/update "subscriptions" record with 123 id.')
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
    subject { instance.update(id, attrs: attrs, locked_by: subscriptions_set.id) }

    let(:id) { subscription.id }
    let(:subscription) { SubscriptionsHelper.create(locked_by: subscriptions_set.id) }
    let(:subscriptions_set) { SubscriptionsSetHelper.create }
    let(:attrs) { { max_restarts_number: 123 } }

    context 'when subscription exists' do
      it 'updates the given attribute' do
        expect { subject }.to change { instance.find_by(id: id)[:max_restarts_number] }.to(123)
      end
      it 'updates updated_at column' do
        expect { subject }.to change { instance.find_by(id: id)[:updated_at] }
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
          raise_error(PgEventstore::RecordNotFound, 'Could not find/update "subscriptions" record with -1 id.')
        )
      end
    end
  end

  describe '#subscriptions_events' do
    subject { instance.subscriptions_events(query_options) }

    let(:query_options) { {} }

    context 'when query_options are absent' do
      it { is_expected.to eq({}) }
    end

    context 'when query_options are present' do
      let(:query_options) do
        {
          runner_id1 => { filter: { event_types: ['Foo'] } },
          runner_id2 => { filter: { streams: [{ context: 'BarCtx' }] } },
        }
      end
      let(:runner_id1) { 1 }
      let(:runner_id2) { 2 }

      let(:stream1) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'foo', stream_id: '2') }
      let!(:event1) do
        event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo')
        PgEventstore.client.append_to_stream(stream1, event)
      end
      let!(:event2) do
        event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar')
        PgEventstore.client.append_to_stream(stream1, event)
      end
      let!(:event3) do
        event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo')
        PgEventstore.client.append_to_stream(stream2, event)
      end
      let!(:link) { PgEventstore.client.link_to(stream1, event3) }

      it 'returns events attributes along with the related runner ids' do
        is_expected.to(
          match(
            {
              runner_id1 => [
                a_hash_including(
                  'id' => event1.id, 'runner_id' => runner_id1, 'type' => 'Foo',
                  **stream1.to_hash.transform_keys(&:to_s)
                ),
                a_hash_including(
                  'id' => event3.id, 'runner_id' => runner_id1, 'type' => 'Foo',
                  **stream2.to_hash.transform_keys(&:to_s)
                ),
              ],
              runner_id2 => [
                a_hash_including(
                  'id' => event1.id, 'runner_id' => runner_id2, 'type' => 'Foo',
                  **stream1.to_hash.transform_keys(&:to_s)
                ),
                a_hash_including(
                  'id' => event2.id, 'runner_id' => runner_id2, 'type' => 'Bar',
                  **stream1.to_hash.transform_keys(&:to_s)
                ),
                a_hash_including(
                  'id' => link.id, 'runner_id' => runner_id2, 'type' => PgEventstore::Event::LINK_TYPE,
                  **stream1.to_hash.transform_keys(&:to_s)
                ),
              ],
            }
          )
        )
      end

      context 'when :resolve_link_tos option is given' do
        let(:query_options) do
          {
            runner_id2 => { filter: { streams: [{ context: 'BarCtx' }] }, resolve_link_tos: true },
          }
        end

        it 'resolves links' do
          is_expected.to(
            match(
              runner_id2 => [
                a_hash_including(
                  'id' => event1.id, 'runner_id' => runner_id2, 'type' => 'Foo',
                  **stream1.to_hash.transform_keys(&:to_s)
                ),
                a_hash_including(
                  'id' => event2.id, 'runner_id' => runner_id2, 'type' => 'Bar',
                  **stream1.to_hash.transform_keys(&:to_s)
                ),
                a_hash_including(
                  'id' => event3.id, 'runner_id' => runner_id2, 'type' => 'Foo',
                  **stream2.to_hash.transform_keys(&:to_s)
                ),
              ]
            )
          )
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

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
          raise_error(PgEventstore::RecordNotFound, "Could not find/update \"subscriptions\" record with 123 id.")
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
    subject { instance.update(id, attrs) }

    let(:id) { subscription.id }
    let(:subscription) { SubscriptionsHelper.create }
    let(:attrs) { { max_restarts_number: 123 } }

    context 'when subscription exists' do
      it 'updates the given attribute' do
        expect { subject }.to change { instance.find_by(id: id)[:max_restarts_number] }.to(123)
      end
      it 'updates updated_at column' do
        expect { subject }.to change { instance.find_by(id: id)[:updated_at] }
      end
      it 'returns updated attributes' do
        is_expected.to match(a_hash_including(id: id, max_restarts_number: 123))
      end

      context 'when subscription is updated by someone else' do
        before do
          instance.update(id, { restart_count: 2 })
        end

        it 'returns those changes as well' do
          is_expected.to match(a_hash_including(id: id, max_restarts_number: 123, restart_count: 2))
        end
      end
    end

    context 'when subscription does not exist' do
      let(:subscription) { PgEventstore::Subscription.new(id: -1) }

      it 'raises error' do
        expect { subject }.to(
          raise_error(PgEventstore::RecordNotFound, "Could not find/update \"subscriptions\" record with -1 id.")
        )
      end
    end
  end

  describe '#subscriptions_events' do
    subject { instance.subscriptions_events(query_options) }

    let(:query_options) { [] }

    context 'when query_options are absent' do
      it { is_expected.to eq([]) }
    end

    context 'when query_options are present' do
      let(:query_options) do
        [
          [runner_id1, { filter: { event_types: ['Foo'] } }],
          [runner_id2, { filter: { streams: [{ context: 'BarCtx' }] } }]
        ]
      end
      let(:runner_id1) { 1 }
      let(:runner_id2) { 2 }

      let(:stream1) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'foo', stream_id: '2') }
      let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar') }
      let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }

      before do
        PgEventstore.client.append_to_stream(stream1, [event1, event2])
        PgEventstore.client.append_to_stream(stream2, event3)
      end

      it 'returns events attributes along with the related runner ids' do
        is_expected.to(
          match(
            [
              a_hash_including(
                'id' => event1.id, 'runner_id' => runner_id1, 'type' => 'Foo',
                'stream' => a_hash_including(stream1.to_hash.transform_keys(&:to_s))
              ),
              a_hash_including(
                'id' => event3.id, 'runner_id' => runner_id1, 'type' => 'Foo',
                'stream' => a_hash_including(stream2.to_hash.transform_keys(&:to_s))
              ),
              a_hash_including(
                'id' => event1.id, 'runner_id' => runner_id2, 'type' => 'Foo',
                'stream' => a_hash_including(stream1.to_hash.transform_keys(&:to_s))
              ),
              a_hash_including(
                'id' => event2.id, 'runner_id' => runner_id2, 'type' => 'Bar',
                'stream' => a_hash_including(stream1.to_hash.transform_keys(&:to_s))
              ),
            ]
          )
        )
      end

      context 'when only one set of query options is given' do
        let(:query_options) do
          [
            [runner_id2, { filter: { streams: [{ context: 'BarCtx' }] } }]
          ]
        end

        it 'returns the result only for it' do
          is_expected.to(
            match(
              [
                a_hash_including(
                  'id' => event1.id, 'runner_id' => runner_id2, 'type' => 'Foo',
                  'stream' => a_hash_including(stream1.to_hash.transform_keys(&:to_s))
                ),
                a_hash_including(
                  'id' => event2.id, 'runner_id' => runner_id2, 'type' => 'Bar',
                  'stream' => a_hash_including(stream1.to_hash.transform_keys(&:to_s))
                )
              ]
            )
          )
        end
      end
    end
  end

  describe '#lock!' do
    subject { instance.lock!(id, lock_id) }

    let(:lock_id) { SecureRandom.uuid }
    let(:id) { 123 }

    context 'when subscription exists' do
      let(:subscription) { SubscriptionsHelper.create }
      let(:id) { subscription.id }

      context 'when subscription is not locked' do
        it 'locks it' do
          expect { subject }.to change { instance.find!(id)[:locked_by] }.to(lock_id)
        end
        it 'returns the given lock id' do
          is_expected.to eq(lock_id)
        end
      end

      context 'when subscription is locked' do
        before do
          instance.update(id, { locked_by: lock_id })
        end

        it 'raises error' do
          expect { subject }.to(
            raise_error(
              PgEventstore::SubscriptionAlreadyLockedError,
              <<~TEXT.strip
                Could not lock Subscription from #{subscription.set.inspect} set with #{subscription.name.inspect} \
                name. It is already locked by #{lock_id.inspect} set.
              TEXT
            )
          )
        end
      end
    end

    context 'when subscription does not exist' do
      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::RecordNotFound)
      end
    end
  end

  describe '#unlock!' do
    subject { instance.unlock!(id, lock_id) }

    let(:lock_id) { SecureRandom.uuid }
    let(:id) { 123 }

    context 'when subscription exists' do
      let(:subscription) { SubscriptionsHelper.create }
      let(:id) { subscription.id }

      context "when subscription's lock id does not match the given lock id" do
        let(:another_lock_id) { SecureRandom.uuid }

        before do
          instance.update(id, { locked_by: another_lock_id })
        end

        it 'raises error' do
          expect { subject }.to(
            raise_error(
              PgEventstore::SubscriptionUnlockError,
              <<~TEXT.strip
                Failed to unlock Subscription from #{subscription.set.inspect} set with #{subscription.name.inspect} \
                name by #{lock_id.inspect} lock id. It is currently locked by #{another_lock_id.inspect} lock id.
              TEXT
            )
          )
        end
      end

      context "when subscription's lock id is nil" do
        it 'raises error' do
          expect { subject }.to raise_error(PgEventstore::SubscriptionUnlockError)
        end
      end

      context "when subscription's lock id matches the given lock id" do
        before do
          instance.update(id, { locked_by: lock_id })
        end

        it 'unlocks the subscription' do
          expect { subject }.to change { instance.find!(id)[:locked_by] }.from(lock_id).to(nil)
        end
      end
    end

    context 'when subscription does not exist' do
      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::RecordNotFound)
      end
    end
  end
end

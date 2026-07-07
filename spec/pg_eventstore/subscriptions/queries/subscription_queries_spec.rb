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

  describe '#create_or_replace_table_function' do
    describe 'creating and replacing function' do
      subject { instance.create_or_replace_table_function(subscription.id, options, subscriptions_set.id) }

      let(:subscription) { SubscriptionsHelper.create }
      let(:subscriptions_set) { SubscriptionsSetHelper.create }
      let(:options) { {} }

      before do
        instance.lock!(subscription.id, subscriptions_set.id, force: false)
      end

      context 'when function does not exist' do
        it 'creates function for the given subscription' do
          expect { subject }.to change {
            query_strategy.exec(<<~SQL).to_a
              select proname from pg_proc where proname like 'subscription_%'
            SQL
          }.from([]).to([{ 'proname' => "subscription_#{subscription.id}" }])
        end
      end

      context 'when function already exists' do
        before do
          instance.create_or_replace_table_function(
            subscription.id,
            { filter: { event_types: ['Foo'] } }, subscriptions_set.id
          )
        end

        it 're-creates it' do
          func_name = "subscription_#{subscription.id}"
          expect { subject }.to change {
            query_strategy.exec_params(<<~SQL, [func_name]).to_a.first&.[]('def')
              select pg_get_functiondef(p.oid) as def from pg_proc p where proname = $1
            SQL
          }.from(a_string_including('Foo'))
        end
      end
    end

    describe 'filtering using created function' do
      subject do
        query = "select * from #{func_name}($1::bigint, $2::bigint, $3::int)"
        query_strategy.exec_params(query, [from_position, to_position, limit]).map do |attrs|
          PgEventstore::EventGlobalIndex::SubscriptionRepr.new(**attrs.transform_keys(&:to_sym))
        end
      end

      let(:subscription) { SubscriptionsHelper.create }
      let(:subscriptions_set) { SubscriptionsSetHelper.create }
      let(:func_name) { "subscription_#{subscription.id}" }
      let(:options) { {} }
      let(:from_position) { 1 }
      let(:to_position) do
        query_strategy.exec(
          'select max(subscription_position) as max_pos from event_subscription_positions'
        ).first['max_pos'] || 0
      end
      let(:limit) { 1_000 }

      before do
        instance.lock!(subscription.id, subscriptions_set.id, force: false)
        instance.create_or_replace_table_function(subscription.id, options, subscriptions_set.id)
      end

      describe 'filtering by stream parts and event types' do
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
          event1
          event2
          event3
          event4
          event5
          PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection).assign_subscription_position
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
                  ],
                },
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
              },
            }
          end

          it 'returns indexes by the given streams and event types filters' do
            is_expected.to eq([event_idx2, event_idx4, event_idx5])
          end

          describe 'from position' do
            let(:from_position) { event_idx3.subscription_position }

            it 'returns indexes from the given position' do
              is_expected.to eq([event_idx4, event_idx5])
            end
          end

          describe 'to position' do
            let(:to_position) { event_idx4.subscription_position }

            it 'returns indexes from the given position' do
              is_expected.to eq([event_idx2, event_idx4])
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_idx1.subscription_position }
            let(:to_position) { event_idx3.subscription_position }

            it 'returns indexes from the given position' do
              is_expected.to eq([event_idx2])
            end
          end
        end
      end

      describe 'filtering by markers' do
        let(:events) { [] }
        let(:indexes) do
          lambda do |ids|
            all_indexes = prepare_subscription_indexes(PgEventstore.client.read(PgEventstore::Stream.all_stream))
            ids.map do |id|
              all_indexes.find { _1.subscription_position == event_position.call(id) }
            end
          end
        end

        let(:event_position) do
          lambda do |id|
            global_position =
              PgEventstore.client.read(PgEventstore::Stream.all_stream).find { _1.data['id'] == id }.global_position
            query_strategy.exec_params(
              'select subscription_position from event_subscription_positions where global_position = $1',
              [global_position]
            ).first['subscription_position']
          end
        end

        before do
          events.each do |stream, event|
            PgEventstore.client.append_to_stream(stream, event)
          end
          PgEventstore::EventSubscriptionPositionQueries.new(PgEventstore.connection).assign_subscription_position
        end

        describe 'matching events by any of the filter markers' do
          let(:options) { { filter: { event_types: [{ markers: %w[foo baz] }] } } }

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

          let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }) }
          let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[foo]) }
          let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[baz]) }
          let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
          let(:event5) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[foo]) }
          let(:event6) { PgEventstore::Event.new(type: 'Bar', data: { id: 6 }, markers: %w[baz]) }
          let(:events) do
            [
              [stream1, event1],
              [stream2, event2],
              [stream1, event3],
              [stream2, event4],
              [stream1, event5],
              [stream2, event6],
            ]
          end

          it 'returns matching indexes from all streams' do
            is_expected.to eq(indexes.call([2, 3, 5, 6]))
          end

          context 'when markers are split into multiple filters' do
            let(:options) { { filter: { event_types: [{ markers: ['foo'] }, { markers: ['baz'] }] } } }

            it 'correctly recognizes them' do
              is_expected.to eq(indexes.call([2, 3, 5, 6]))
            end
          end

          describe 'from position' do
            let(:from_position) { event_position.call(5) }

            it 'returns matching events from the given global position' do
              is_expected.to eq(indexes.call([5, 6]))
            end
          end

          describe 'to position' do
            let(:to_position) { event_position.call(3) }

            it 'returns matching events to the given global position' do
              is_expected.to eq(indexes.call([2, 3]))
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_position.call(3) }
            let(:to_position) { event_position.call(5) }

            it 'returns matching events within the given global position range' do
              is_expected.to eq(indexes.call([3, 5]))
            end
          end
        end

        describe 'matching events by mix of type and marker' do
          let(:options) { { filter: { event_types: [{ markers: %w[bar] }, { type: 'Foo', markers: ['baz'] }] } } }

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

          let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[baz]) }
          let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[foo]) }
          let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[bar]) }
          let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
          let(:event5) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[baz]) }
          let(:event6) { PgEventstore::Event.new(type: 'Foo', data: { id: 6 }, markers: %w[foo]) }
          let(:events) do
            [
              [stream1, event1],
              [stream2, event2],
              [stream1, event3],
              [stream2, event4],
              [stream1, event5],
              [stream2, event6],
            ]
          end

          it 'returns matching events' do
            is_expected.to eq(indexes.call([1, 3, 4, 5]))
          end

          describe 'from position' do
            let(:from_position) { event_position.call(3) }

            it 'returns matching events from the given global position' do
              is_expected.to eq(indexes.call([3, 4, 5]))
            end
          end

          describe 'to position' do
            let(:to_position) { event_position.call(4) }

            it 'returns matching events to the given global position' do
              is_expected.to eq(indexes.call([1, 3, 4]))
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_position.call(2) }
            let(:to_position) { event_position.call(4) }

            it 'returns matching events within the given global position range' do
              is_expected.to eq(indexes.call([3, 4]))
            end
          end
        end

        describe 'matching events by context and markers' do
          let(:options) { { filter: { streams: [{ context: 'FooCtx' }], event_types: [{ markers: %w[foo bar] }] } } }

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
          let(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Foo', stream_id: '1') }

          let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[foo]) }
          let(:event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 2 }, markers: %w[bar]) }
          let(:event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 3 }, markers: %w[foo bar]) }
          let(:event4) { PgEventstore::Event.new(type: 'Baz', data: { id: 4 }, markers: %w[bar]) }
          let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[bar]) }
          let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[foo bar]) }
          let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[baz]) }
          let(:unmatched_event4) { PgEventstore::Event.new(type: 'Baz', data: { id: 8 }, markers: %w[foo]) }

          let(:events) do
            [
              [stream1, event1],
              [stream2, event2],
              [stream3, unmatched_event1],
              [stream1, event3],
              [stream3, unmatched_event2],
              [stream3, unmatched_event3],
              [stream2, event4],
              [stream3, unmatched_event4],
            ]
          end

          it 'returns matching events' do
            is_expected.to eq(indexes.call([1, 2, 3, 4]))
          end

          describe 'from position' do
            let(:from_position) { event_position.call(3) }

            it 'returns matching events from the given global position' do
              is_expected.to eq(indexes.call([3, 4]))
            end
          end

          describe 'to position' do
            let(:to_position) { event_position.call(3) }

            it 'returns matching events to the given global position' do
              is_expected.to eq(indexes.call([1, 2, 3]))
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_position.call(2) }
            let(:to_position) { event_position.call(4) }

            it 'returns matching events within the given global position range' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end
        end

        describe 'matching events by context, stream name and markers' do
          let(:options) do
            {
              filter: {
                streams: [{ context: 'FooCtx', stream_name: 'Foo' }],
                event_types: [{ markers: %w[foo bar] }],
              },
            }
          end

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
          let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

          let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[foo]) }
          let(:event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 2 }, markers: %w[bar]) }
          let(:event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 3 }, markers: %w[foo bar]) }
          let(:event4) { PgEventstore::Event.new(type: 'Baz', data: { id: 4 }, markers: %w[bar]) }
          let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[bar]) }
          let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[foo bar]) }
          let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[baz]) }
          let(:unmatched_event4) { PgEventstore::Event.new(type: 'Baz', data: { id: 8 }, markers: %w[foo]) }

          let(:events) do
            [
              [stream1, event1],
              [stream2, event2],
              [stream3, unmatched_event1],
              [stream1, event3],
              [stream3, unmatched_event2],
              [stream3, unmatched_event3],
              [stream2, event4],
              [stream3, unmatched_event4],
            ]
          end

          it 'returns matching events' do
            is_expected.to eq(indexes.call([1, 2, 3, 4]))
          end

          describe 'from position' do
            let(:from_position) { event_position.call(3) }

            it 'returns matching events from the given global position' do
              is_expected.to eq(indexes.call([3, 4]))
            end
          end

          describe 'to position' do
            let(:to_position) { event_position.call(3) }

            it 'returns matching events to the given global position' do
              is_expected.to eq(indexes.call([1, 2, 3]))
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_position.call(2) }
            let(:to_position) { event_position.call(4) }

            it 'returns matching events within the given global position range' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end
        end

        describe 'matching events by context and markers with event types' do
          let(:options) do
            { filter: { streams: [{ context: 'FooCtx' }], event_types: [{ type: 'Bar', markers: %w[bar foo] }] } }
          end

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
          let(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

          let(:event1) { PgEventstore::Event.new(type: 'Bar', data: { id: 1 }, markers: %w[foo]) }
          let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
          let(:event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 3 }, markers: %w[foo bar]) }
          let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
          let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[bar]) }
          let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[bar]) }
          let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[baz]) }
          let(:unmatched_event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 8 }, markers: %w[bar]) }

          let(:events) do
            [
              [stream1, unmatched_event1],
              [stream1, event1],
              [stream2, unmatched_event2],
              [stream2, event2],
              [stream1, unmatched_event3],
              [stream1, event3],
              [stream2, event4],
              [stream3, unmatched_event4],
            ]
          end

          it 'returns matching events' do
            is_expected.to eq(indexes.call([1, 2, 3, 4]))
          end

          describe 'from position' do
            let(:from_position) { event_position.call(2) }

            it 'returns matching events from the given global position' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end

          describe 'to position' do
            let(:to_position) { event_position.call(2) }

            it 'returns matching events to the given global position' do
              is_expected.to eq(indexes.call([1, 2]))
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_position.call(2) }
            let(:to_position) { event_position.call(4) }

            it 'returns matching events within the given global position range' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end
        end

        describe 'matching events by context, stream name and markers with event types' do
          let(:options) do
            {
              filter: {
                streams: [{ context: 'FooCtx', stream_name: 'Foo' }],
                event_types: [{ type: 'Bar', markers: %w[bar foo] }],
              },
            }
          end

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
          let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

          let(:event1) { PgEventstore::Event.new(type: 'Bar', data: { id: 1 }, markers: %w[foo]) }
          let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
          let(:event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 3 }, markers: %w[foo bar]) }
          let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
          let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[bar]) }
          let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[bar]) }
          let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[baz]) }
          let(:unmatched_event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 8 }, markers: %w[bar]) }

          let(:events) do
            [
              [stream1, unmatched_event1],
              [stream1, event1],
              [stream2, unmatched_event2],
              [stream2, event2],
              [stream1, unmatched_event3],
              [stream1, event3],
              [stream2, event4],
              [stream3, unmatched_event4],
            ]
          end

          it 'returns matching events' do
            is_expected.to eq(indexes.call([1, 2, 3, 4]))
          end

          describe 'from position' do
            let(:from_position) { event_position.call(2) }

            it 'returns matching events from the given global position' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end

          describe 'to position' do
            let(:to_position) { event_position.call(2) }

            it 'returns matching events to the given global position' do
              is_expected.to eq(indexes.call([1, 2]))
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_position.call(2) }
            let(:to_position) { event_position.call(4) }

            it 'returns matching events within the given global position range' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end
        end

        describe 'matching events by stream and markers' do
          let(:options) { { filter: { streams: [stream1.to_hash], event_types: [{ markers: %w[bar foo] }] } } }

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

          let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[foo]) }
          let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
          let(:event3) { PgEventstore::Event.new(type: 'Baz', data: { id: 3 }, markers: %w[foo bar]) }
          let(:event4) { PgEventstore::Event.new(type: 'FooBar', data: { id: 4 }, markers: %w[bar]) }
          let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[baz]) }
          let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[foo-baz]) }
          let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[foo]) }

          let(:events) do
            [
              [stream1, unmatched_event1],
              [stream1, event1],
              [stream1, unmatched_event2],
              [stream1, event2],
              [stream2, unmatched_event3],
              [stream1, event3],
              [stream1, event4],
            ]
          end

          it 'returns matching events' do
            is_expected.to eq(indexes.call([1, 2, 3, 4]))
          end

          describe 'from position' do
            let(:from_position) { event_position.call(2) }

            it 'returns matching events from the given global position' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end

          describe 'to position' do
            let(:to_position) { event_position.call(2) }

            it 'returns matching events to the given global position' do
              is_expected.to eq(indexes.call([1, 2]))
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_position.call(2) }
            let(:to_position) { event_position.call(4) }

            it 'returns matching events within the given global position range' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end
        end

        describe 'matching events by stream and markers with event types' do
          let(:options) do
            { filter: { streams: [stream1.to_hash], event_types: [{ type: 'Bar', markers: %w[bar foo] }] } }
          end

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

          let(:event1) { PgEventstore::Event.new(type: 'Bar', data: { id: 1 }, markers: %w[foo]) }
          let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
          let(:event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 3 }, markers: %w[foo bar]) }
          let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
          let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[foo bar]) }
          let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[bar]) }
          let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[bar]) }

          let(:events) do
            [
              [stream1, unmatched_event1],
              [stream1, event1],
              [stream1, unmatched_event2],
              [stream1, event2],
              [stream2, unmatched_event3],
              [stream1, event3],
              [stream1, event4],
            ]
          end

          it 'returns matching events' do
            is_expected.to eq(indexes.call([1, 2, 3, 4]))
          end

          describe 'from position' do
            let(:from_position) { event_position.call(2) }

            it 'returns matching events from the given global position' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end

          describe 'to position' do
            let(:to_position) { event_position.call(2) }

            it 'returns matching events to the given global position' do
              is_expected.to eq(indexes.call([1, 2]))
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_position.call(2) }
            let(:to_position) { event_position.call(4) }

            it 'returns matching events within the given global position range' do
              is_expected.to eq(indexes.call([2, 3, 4]))
            end
          end
        end

        describe 'custom to position, from position and limit' do
          let(:options) do
            {
              filter: {
                event_types: [
                  { markers: %w[foo] },
                  { type: 'Bar', markers: %w[bar] },
                ],
              },
            }
          end
          let(:from_position) { event_position.call(3) }
          let(:to_position) { event_position.call(6) }
          let(:limit) { 3 }

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

          let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }) }
          let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[foo]) }
          let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[foo]) }
          let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[foo bar]) }
          let(:event5) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[baz]) }
          let(:event6) { PgEventstore::Event.new(type: 'Bar', data: { id: 6 }, markers: %w[bar]) }
          let(:event7) { PgEventstore::Event.new(type: 'Foo', data: { id: 7 }, markers: %w[baz]) }
          let(:events) do
            [
              [stream1, event1],
              [stream2, event2],
              [stream1, event3],
              [stream2, event4],
              [stream1, event5],
              [stream2, event6],
              [stream1, event7],
            ]
          end

          it 'returns matching events in the given order, within the given global position range' do
            is_expected.to eq(indexes.call([3, 4, 6]))
          end
        end

        describe 'matching events do not exist' do
          let(:options) { { filter: { event_types: [{ markers: %w[foo] }] } } }

          let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

          let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[bar]) }
          let(:event2) { PgEventstore::Event.new(type: 'Foo', data: { id: 2 }, markers: %w[baz]) }
          let(:events) { [[stream, event1], [stream, event2]] }

          it { is_expected.to eq([]) }
        end

        describe 'filtering by mix of marker filters and regular event type filters' do
          let(:options) do
            {
              filter: {
                streams: [{ context: 'FooCtx' }, { context: 'BarCtx', stream_name: 'Bar' }],
                event_types: [{ markers: %w[bar] }, { type: 'Foo', markers: ['baz'] }, 'Bar'],
              },
            }
          end

          let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }
          let(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Baz', stream_id: '1') }

          let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[baz]) }
          let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
          let(:event3) { PgEventstore::Event.new(type: 'FooBar', data: { id: 3 }, markers: %w[bar]) }
          let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }) }
          let(:event5) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[bar]) }
          let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 6 }, markers: %w[baz]) }
          let(:unmatched_event2) { PgEventstore::Event.new(type: 'Baz', data: { id: 7 }, markers: %w[bar]) }
          let(:events) do
            [
              [stream1, event1],
              [stream1, event2],
              [stream1, event3],
              [stream2, event4],
              [stream2, event5],
              [stream3, unmatched_event1],
              [stream3, unmatched_event2],
            ]
          end

          it 'returns matching events once in the given order' do
            is_expected.to eq(indexes.call([1, 2, 3, 4, 5]))
          end

          describe 'from position' do
            let(:from_position) { event_position.call(3) }

            it 'returns matching events from the given global position' do
              is_expected.to eq(indexes.call([3, 4, 5]))
            end
          end

          describe 'to position' do
            let(:to_position) { event_position.call(4) }

            it 'returns matching events to the given global position' do
              is_expected.to eq(indexes.call([1, 2, 3, 4]))
            end
          end

          describe 'from position and to position' do
            let(:from_position) { event_position.call(2) }
            let(:to_position) { event_position.call(5) }

            it 'returns matching events within the given global position range' do
              is_expected.to eq(indexes.call([2, 3, 4, 5]))
            end
          end

          describe 'limit' do
            let(:limit) { 3 }

            it 'limits the distinct matching events' do
              is_expected.to eq(indexes.call([1, 2, 3]))
            end
          end
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

    before do
      instance.create_or_replace_table_function(subscription.id, {}, nil)
    end

    it 'deletes the given subscriptions' do
      expect { subject }.to change { instance.find_by(id: subscription.id) }.to(nil)
    end
    it 'deletes related table function' do
      expect { subject }.to change {
        query_strategy.exec_params(<<~SQL, ["subscription_#{subscription.id}"]).to_a
          select proname from pg_proc where proname = $1
        SQL
      }.to([])
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

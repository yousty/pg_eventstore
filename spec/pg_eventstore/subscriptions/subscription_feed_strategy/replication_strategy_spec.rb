# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeedStrategy::ReplicationStrategy do
  let(:instance) { described_class.new(connection, query_strategy) }
  let(:connection) { PgEventstore.connection }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(connection) }

  it 'implements SubscriptionFeedStrategy' do
    expect(described_class.allocate).to be_a(PgEventstore::SubscriptionFeedStrategy)
  end

  describe '#add' do
    subject { instance.add(runner1, runner2) }

    let(:runner1) { PgEventstore::ReplicaSubscriptionRunner.allocate }
    let(:runner2) { PgEventstore::ReplicaSubscriptionRunner.allocate }

    it 'adds given runners' do
      expect { subject }.to change { instance.instance_variable_get(:@runners) }.to([runner1, runner2])
    end
  end

  describe '#size' do
    subject { instance.size }

    before do
      instance.add(PgEventstore::ReplicaSubscriptionRunner.allocate, PgEventstore::ReplicaSubscriptionRunner.allocate)
    end

    it 'returns runners size' do
      is_expected.to eq(2)
    end
  end

  describe '#any?' do
    subject { instance.any? }

    context 'when runners are absent' do
      it { is_expected.to eq(false) }
    end

    context 'when runners are present' do
      before do
        instance.add(PgEventstore::ReplicaSubscriptionRunner.allocate)
      end

      it { is_expected.to eq(true) }
    end
  end

  describe '#feed' do
    subject do
      instance.feed
      sleep 0.2 # Wait for the events to process if any
    end

    let(:subscription1) do
      SubscriptionsHelper.create_with_connection(
        name: 's1', set: 'Set1', options: { filter: { event_types: ['Foo'] }, from_position: from_position_sub1 }
      )
    end
    let(:subscription2) do
      SubscriptionsHelper.create_with_connection(
        name: 's2', set: 'Set1', options: { filter: { event_types: ['Bar'] } }
      )
    end
    let(:subscriptions_set) { SubscriptionsSetHelper.create_with_connection(name: 'Set1') }

    let(:from_position_sub1) { 0 }

    let(:runner1) do
      PgEventstore::ReplicaSubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(
          graceful_shutdown_timeout: 0,
          consumer: PgEventstore::EventsProcessorConsumer::Replica.new(handler1)
        ),
        subscription: subscription1
      )
    end
    let(:runner2) do
      PgEventstore::ReplicaSubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(
          graceful_shutdown_timeout: 0,
          consumer: PgEventstore::EventsProcessorConsumer::Replica.new(handler2)
        ),
        subscription: subscription2
      )
    end

    let(:processed_events1) { [] }
    let(:processed_events2) { [] }

    let(:handler1) { proc { |events_sub_idx| processed_events1.push(*events_sub_idx.map(&:global_position)) } }
    let(:handler2) { proc { |events_sub_idx| processed_events2.push(*events_sub_idx.map(&:global_position)) } }

    before do
      # Stub timeout to allow faster attempts to pick events to process
      stub_const('PgEventstore::EventsProcessorConsumer::Replica::EVENT_WAIT_TIMEOUT', 0.1)
      subscription1.lock!(subscriptions_set.id)
      subscription2.lock!(subscriptions_set.id)
      instance.add(runner1, runner2)
      runner1.start
      runner2.start
      # Set events global_position sequence value to easily test :to_position. 123 will be the global_position of the
      # first created event
      reset_events_subscription_position(123)
    end

    after do
      runner1.stop_async
      runner2.stop_async
      runner1.wait_for_finish
      runner2.wait_for_finish
    end

    context 'when indexes does not exist' do
      it 'checkpoints first subscription' do
        expect { subject }.to change {
          subscription1.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
        }.to([0, 0])
      end
      it 'checkpoints second subscription' do
        expect { subject }.to change {
          subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
        }.to([0, 0])
      end
    end

    context 'when indexes exist for first subscription' do
      let!(:events) do
        event = PgEventstore::Event.new(type: 'Foo')
        stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
        Array.new(2) { PgEventstore.client.append_to_stream(stream, event) }
      end
      let!(:indexes) { prepare_subscription_indexes(events) }

      describe 'default behavior' do
        it 'processes events' do
          expect { subject }.to change {
            dv(processed_events1).deferred_wait(timeout: 0.5) { _1.size == 1 }
          }.to(events.map(&:global_position))
        end
        it 'checkpoints second subscription' do
          expect { subject }.to change {
            subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([indexes.last.subscription_position, indexes.last.subscription_position])
        end
      end

      context "when index look up distance is less than event's position" do
        before do
          stub_const("#{described_class}::INDEX_LOOK_UP_DISTANCE", 10)
        end

        it 'does not process the event' do
          expect { subject }.not_to change { dv(processed_events1).deferred_wait(timeout: 0.1) { _1.size == 1 } }
        end
        it 'checkpoints first subscription' do
          expect { subject }.to change {
            subscription1.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([11, 11])
        end
        it 'checkpoints second subscription' do
          expect { subject }.to change {
            subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([11, 11])
        end
      end

      context "when :from_position is greater than event's position" do
        let(:from_position_sub1) { indexes.last.subscription_position + 10 }

        it 'does not process the event' do
          expect { subject }.not_to change { dv(processed_events1).deferred_wait(timeout: 0.1) { _1.size == 1 } }
        end
        it 'checkpoints first subscription' do
          expect { subject }.to change {
            subscription1.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([indexes.last.subscription_position, indexes.last.subscription_position])
        end
        it 'checkpoints second subscription' do
          expect { subject }.to change {
            subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([indexes.last.subscription_position, indexes.last.subscription_position])
        end
      end

      context 'when subscription limits max number of events to fetch' do
        before do
          allow(runner1).to receive(:next_chunk_query_opts).and_wrap_original do |orig_meth|
            orig_meth.call.tap do |attrs|
              attrs[:max_count] = 1
            end
          end
        end

        it 'processes only one event' do
          expect { subject }.to change {
            dv(processed_events1).deferred_wait(timeout: 0.5) { _1.size == 2 }
          }.to([events.first.global_position])
        end
      end
    end
  end
end

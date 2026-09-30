# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeedStrategy::IndexReadStrategy do
  let(:instance) { described_class.new(connection, query_strategy) }
  let(:connection) { PgEventstore.connection }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(connection) }

  it 'implements SubscriptionFeedStrategy' do
    expect(described_class.allocate).to be_a(PgEventstore::SubscriptionFeedStrategy)
  end

  describe '#add' do
    subject { instance.add(runner, query_options) }

    let(:runner) { PgEventstore::SubscriptionRunner.allocate }
    let(:query_options) { { from_position: 1, to_position: 2, max_count: 10, resolve_link_tos: false } }

    it 'adds given runner along with its query options' do
      expect { subject }.to change {
        instance.instance_variable_get(:@runners_query_options)
      }.to(runner => query_options)
    end
  end

  describe '#size' do
    subject { instance.size }

    before do
      instance.add(PgEventstore::SubscriptionRunner.allocate, {})
      instance.add(PgEventstore::SubscriptionRunner.allocate, {})
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
        instance.add(PgEventstore::SubscriptionRunner.allocate, {})
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
      SubscriptionsHelper.create_with_connection(name: 's1', set: 'Set1', options: { filter: { event_types: ['Foo'] } })
    end
    let(:subscription2) do
      SubscriptionsHelper.create_with_connection(name: 's2', set: 'Set1', options: { filter: { event_types: ['Bar'] } })
    end
    let(:subscriptions_set) { SubscriptionsSetHelper.create_with_connection(name: 'Set1') }

    let(:runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(
          graceful_shutdown_timeout: 0,
          consumer: PgEventstore::EventsProcessorConsumer::Single.new(handler1)
        ),
        subscription: subscription1
      )
    end
    let(:runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(
          graceful_shutdown_timeout: 0,
          consumer: PgEventstore::EventsProcessorConsumer::Single.new(handler2)
        ),
        subscription: subscription2
      )
    end

    let(:query_options1) do
      { from_position: from_position_sub1, to_position:, max_count: max_count_sub1, resolve_link_tos: false }
    end
    let(:query_options2) { { from_position: 1, to_position:, max_count: 10, resolve_link_tos: false } }
    let(:from_position_sub1) { 1 }
    let(:max_count_sub1) { 10 }
    let(:to_position) { 0 }

    let(:processed_events1) { [] }
    let(:processed_events2) { [] }

    let(:handler1) { proc { |raw_event| processed_events1.push(raw_event['global_position']) } }
    let(:handler2) { proc { |raw_event| processed_events2.push(raw_event['global_position']) } }

    before do
      # Stub timeout to allow faster attempts to pick events to process
      stub_const('PgEventstore::EventsProcessorConsumer::Single::EVENT_WAIT_TIMEOUT', 0.1)
      # Set events global_position sequence value to easily test :to_position. 123 will be the global_position of the
      # first created event
      reset_events_subscription_position(123)
      subscription1.lock!(subscriptions_set.id)
      subscription2.lock!(subscriptions_set.id)
      instance.add(runner1, query_options1)
      instance.add(runner2, query_options2)
      runner1.start
      runner2.start
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
      let!(:event) do
        event = PgEventstore::Event.new(type: 'Foo')
        stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
        PgEventstore.client.append_to_stream(stream, event)
      end
      let!(:index) { prepare_subscription_indexes([event]).first }
      let(:to_position) { index.subscription_position }

      describe 'default behavior' do
        it 'processes the event' do
          expect { subject }.to change {
            dv(processed_events1).deferred_wait(timeout: 0.5) { _1.size == 1 }
          }.to([event.global_position])
        end
        it 'checkpoints second subscription' do
          expect { subject }.to change {
            subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([index.subscription_position, index.subscription_position])
        end
      end

      context "when :to_position is less than event's position" do
        let(:to_position) { 11 }

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
        let(:from_position_sub1) { index.subscription_position + 10 }

        it 'does not process the event' do
          expect { subject }.not_to change { dv(processed_events1).deferred_wait(timeout: 0.1) { _1.size == 1 } }
        end
        it 'checkpoints first subscription' do
          expect { subject }.to change {
            subscription1.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([index.subscription_position, index.subscription_position])
        end
        it 'checkpoints second subscription' do
          expect { subject }.to change {
            subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([index.subscription_position, index.subscription_position])
        end
      end

      context 'when :max_count limits the number of events to fetch' do
        let!(:another_event) do
          event = PgEventstore::Event.new(type: 'Foo')
          stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
          PgEventstore.client.append_to_stream(stream, event)
        end
        let(:max_count_sub1) { 1 }

        it 'processes only one event' do
          expect { subject }.to change {
            dv(processed_events1).deferred_wait(timeout: 0.5) { _1.size == 2 }
          }.to([event.global_position])
        end
      end
    end
  end
end

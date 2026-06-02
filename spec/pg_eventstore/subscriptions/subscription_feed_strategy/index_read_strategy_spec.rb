# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionFeedStrategy::IndexReadStrategy do
  let(:instance) { described_class.new(connection, query_strategy) }
  let(:connection) { PgEventstore.connection }
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(connection) }

  it 'implements SubscriptionFeedStrategy' do
    expect(described_class.allocate).to be_a(PgEventstore::SubscriptionFeedStrategy)
  end

  describe '#add' do
    subject { instance.add(runner1, runner2) }

    let(:runner1) { PgEventstore::SubscriptionRunner.allocate }
    let(:runner2) { PgEventstore::SubscriptionRunner.allocate }

    it 'adds given runners' do
      expect { subject }.to change { instance.instance_variable_get(:@runners) }.to([runner1, runner2])
    end
  end

  describe '#size' do
    subject { instance.size }

    before do
      instance.add(PgEventstore::SubscriptionRunner.allocate, PgEventstore::SubscriptionRunner.allocate)
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
        instance.add(PgEventstore::SubscriptionRunner.allocate)
      end

      it { is_expected.to eq(true) }
    end
  end

  describe '#feed' do
    subject { instance.feed(safe_position) }

    let(:safe_position) { 150 }

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

    let(:processed_events1) { [] }
    let(:processed_events2) { [] }

    let(:handler1) { proc { |raw_event| processed_events1.push(raw_event['global_position']) } }
    let(:handler2) { proc { |raw_event| processed_events2.push(raw_event['global_position']) } }

    before do
      subscription1.lock!(subscriptions_set.id)
      subscription2.lock!(subscriptions_set.id)
      instance.add(runner1, runner2)
      runner1.start
      runner2.start
      # Set events global_position sequence value to easily test safe position
      query_strategy.exec("select setval('events_global_position_seq'::regclass, 123, false)")
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
        }.to([safe_position, safe_position])
      end
      it 'checkpoints second subscription' do
        expect { subject }.to change {
          subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
        }.to([safe_position, safe_position])
      end
    end

    context 'when indexes exist for first subscription' do
      let!(:event) do
        event = PgEventstore::Event.new(type: 'Foo')
        stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
        PgEventstore.client.append_to_stream(stream, event)
      end

      context 'when safe position is less than the position of existing event' do
        let(:safe_position) { 10 }

        it 'does not process it' do
          expect { subject }.not_to change { dv(processed_events1).deferred_wait(timeout: 0.1) { _1.size == 1 } }
        end
        it 'checkpoints first subscription' do
          expect { subject }.to change {
            subscription1.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([safe_position, safe_position])
        end
        it 'checkpoints second subscription' do
          expect { subject }.to change {
            subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([safe_position, safe_position])
        end
      end

      context 'when safe position is greater than or equal to the position of existing event' do
        let(:safe_position) { event.global_position }

        it 'processes it by first subscription' do
          expect { subject }.to change {
            dv(processed_events1).deferred_wait(timeout: 0.1) { _1.size == 1 }
          }.to([event.global_position])
        end
        it 'does not process by of second subscription' do
          expect { subject }.not_to change { dv(processed_events2).deferred_wait(timeout: 0.1) { _1.size == 1 } }
        end
        it 'checkpoints second subscription' do
          expect { subject }.to change {
            subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([safe_position, safe_position])
        end
      end

      context "when index look up distance is less than event's position" do
        let(:safe_position) { event.global_position + 10 }

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
        let(:from_position_sub1) { event.global_position }
        let(:safe_position) { event.global_position + 20 }

        before do
          stub_const("#{described_class}::INDEX_LOOK_UP_DISTANCE", 10)
        end

        it 'does not process the event' do
          expect { subject }.not_to change { dv(processed_events1).deferred_wait(timeout: 0.1) { _1.size == 1 } }
        end
        it 'checkpoints first subscription' do
          checkpoint = from_position_sub1 + described_class::INDEX_LOOK_UP_DISTANCE + 1
          expect { subject }.to change {
            subscription1.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([checkpoint, checkpoint])
        end
        it 'checkpoints second subscription' do
          checkpoint = described_class::INDEX_LOOK_UP_DISTANCE + 1
          expect { subject }.to change {
            subscription2.reload.options_hash.values_at(:current_position, :last_chunk_greatest_position)
          }.to([checkpoint, checkpoint])
        end
      end

      context 'when subscription limits max number of events to fetch' do
        let!(:another_event) do
          event = PgEventstore::Event.new(type: 'Foo')
          stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
          PgEventstore.client.append_to_stream(stream, event)
        end

        before do
          allow(runner1).to receive(:next_chunk_query_opts).and_wrap_original do |orig_meth|
            orig_meth.call.tap do |attrs|
              attrs[:max_count] = 1
            end
          end
        end

        it 'processes only one event' do
          expect { subject }.to change {
            dv(processed_events1).deferred_wait(timeout: 0.1) { _1.size == 2 }
          }.to([event.global_position])
        end
      end
    end
  end
end

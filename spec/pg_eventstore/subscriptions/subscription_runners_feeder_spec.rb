# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionRunnersFeeder do
  let(:instance) { described_class.new(config_name) }
  let(:config_name) { :default }

  describe '#feed' do
    subject { instance.feed(runners) }

    context 'when there are no runners' do
      let(:runners) { [] }

      it { is_expected.to eq(nil) }
    end

    context 'when there are runners' do
      let(:runners) { [runner] }

      let(:runner) do
        PgEventstore::SubscriptionRunner.new(
          stats:,
          events_processor: PgEventstore::EventsProcessor.new(
            consumer: PgEventstore::EventsProcessorConsumer::Single.new(handler),
            graceful_shutdown_timeout: 0
          ),
          subscription:
        )
      end
      let(:stats) { PgEventstore::SubscriptionHandlerPerformance.new }
      let(:handler) { proc {} }
      let(:subscription) { SubscriptionsHelper.create_with_connection(name: 'Foo', set: 'FooSet') }
      let(:subscriptions_set) { SubscriptionsSetHelper.create_with_connection(name: 'FooSet') }

      before do
        subscription.lock!(subscriptions_set.id)
        allow(runner).to receive(:feed).and_call_original
      end

      after do
        runner.stop_async.wait_for_finish
      end

      context 'when runner is running' do
        before do
          runner.start
        end

        context 'when runner is idle' do
          it 'processes it' do
            subject
            expect(runner).to have_received(:feed).with(kind_of(PgEventstore::Chunks::SubscriptionCheckpointChunk))
          end
        end

        context 'when runner was fed recently' do
          before do
            subscription.update(last_chunk_fed_at: Time.now.utc)
          end

          it 'does not process it' do
            subject
            expect(runner).not_to have_received(:feed)
          end
        end

        context 'when runner has enough events in the queue' do
          let(:handler) { proc { sleep 0.1 } }
          let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(100) { PgEventstore::Event.new }) }
          let(:indexes) { prepare_subscription_indexes(events) }

          before do
            stats.track_exec_time(1) { sleep 0.2 }
            runner.feed(create_subscription_index_chunk(indexes))
            subscription.update(last_chunk_fed_at: PgEventstore::Subscription::DEFAULT_TIMESTAMP)
            dv.wait_until(timeout: 1) { subscription.reload.total_processed_events > 0 }
          end

          it 'does not process it' do
            subject
            expect(runner).to have_received(:feed).once
          end
        end

        context 'when events exist' do
          let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }
          let(:index) { prepare_subscription_indexes([event]).first }

          before do
            # Set events global_position sequence value to easily test :to_position. 123 will be the global_position
            # of the first created event
            reset_events_subscription_position(123)
            index
          end

          it 'processes it' do
            subject
            expect(runner).to have_received(:feed).with(kind_of(PgEventstore::Chunks::SubscriptionEventsIndexChunk))
          end

          context "when index look up distance is less than event's position" do
            before do
              stub_const("#{described_class}::INDEX_LOOK_UP_DISTANCE", 10)
            end

            it 'checkpoints subscription at the look up distance' do
              expect { subject }.to change { subscription.reload.last_chunk_greatest_position }.to(11)
            end
          end
        end
      end

      context 'when runner is not running' do
        it 'does not process it' do
          subject
          expect(runner).not_to have_received(:feed)
        end
      end
    end
  end
end

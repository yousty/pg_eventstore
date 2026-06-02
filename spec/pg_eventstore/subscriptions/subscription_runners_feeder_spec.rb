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
          stats: PgEventstore::SubscriptionHandlerPerformance.new,
          events_processor: PgEventstore::EventsProcessor.new(
            consumer: PgEventstore::EventsProcessorConsumer::Single.new(proc {}),
            graceful_shutdown_timeout: 0
          ),
          subscription: subscription
        )
      end
      let(:subscription) { SubscriptionsHelper.create_with_connection(name: 'Foo', set: 'FooSet') }
      let(:subscriptions_set) { SubscriptionsSetHelper.create_with_connection(name: 'FooSet') }

      before do
        subscription.lock!(subscriptions_set.id)
        allow(runner).to receive(:checkpoint).and_call_original
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
            expect(runner).to have_received(:checkpoint).with(kind_of(Integer))
          end
        end

        context 'when runner is busy' do
          before do
            allow(runner).to receive(:time_to_feed?).and_return(false)
          end

          it 'does not process it' do
            subject
            expect(runner).not_to have_received(:checkpoint)
          end
        end
      end

      context 'when runner is not running' do
        it 'does not process it' do
          subject
          expect(runner).not_to have_received(:checkpoint)
        end
      end
    end
  end
end

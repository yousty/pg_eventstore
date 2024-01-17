# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionRunner do
  let(:instance) do
    PgEventstore::SubscriptionRunner.new(stats: stats, events_processor: events_processor, subscription: subscription)
  end
  let(:stats) { PgEventstore::SubscriptionHandlerPerformance.new }
  let(:events_processor) { PgEventstore::EventsProcessor.new(handler) }
  let(:subscription) { SubscriptionsHelper.create_with_connection(name: 'Foo') }
  let(:handler) { proc { } }

  describe '#next_chunk_query_opts' do
    subject { instance.next_chunk_query_opts }

    describe ':from_position' do
      context 'when Subscription#last_chunk_greatest_position is present' do
        before do
          subscription.update(last_chunk_greatest_position: 11)
        end

        it 'uses its value to calculate :from_position option value' do
          is_expected.to include(from_position: 12)
        end

        context 'when Subscription#current_position and Subscription#options[:from_position] are present' do
          before do
            subscription.update(current_position: 20, options: { from_position: 21 })
          end

          it 'still relies on #last_chunk_greatest_position' do
            is_expected.to include(from_position: 12)
          end
        end
      end

      context 'when Subscription#current_position is present' do
        before do
          subscription.update(current_position: 11)
        end

        it 'uses its value to calculate :from_position option value' do
          is_expected.to include(from_position: 12)
        end

        context 'when Subscription#options[:from_position] is present' do
          before do
            subscription.update(options: { from_position: 21 })
          end

          it 'still relies on #current_position' do
            is_expected.to include(from_position: 12)
          end
        end
      end

      context 'when Subscription has :from_position option value, persisted in #options' do
        before do
          subscription.update(options: { from_position: 11 })
        end

        it 'uses its value to calculate final :from_position option value' do
          is_expected.to include(from_position: 12)
        end
      end

      context 'when Subscription does not have any persisted position value' do
        it 'uses default value for :from_position option' do
          is_expected.to include(from_position: 1)
        end
      end
    end

    describe ':max_count' do
      context 'when stats does not have any measurements yet' do
        it 'returns default value of :max_count' do
          is_expected.to include(max_count: described_class::INITIAL_EVENTS_PER_CHUNK)
        end
      end

      context 'when Subscription#options[:max_count] is present' do
        before do
          subscription.update(options: { max_count: 123 })
        end

        it 'ignores it' do
          is_expected.to include(max_count: described_class::INITIAL_EVENTS_PER_CHUNK)
        end
      end

      context 'when stats has some measurements already' do
        let(:chunk_query_interval) { 2 }

        before do
          subscription.update(chunk_query_interval: chunk_query_interval)
        end

        context 'when average exec time is normal' do
          before do
            stats.track_exec_time { sleep 0.2 }
            stats.track_exec_time { sleep 0.1 }
          end

          it 'calculates approximate events number of :max_count' do
            is_expected.to include(max_count: chunk_query_interval / stats.average_event_time)
          end

          context 'when there are events left in the queue' do
            before do
              events_processor.feed([{ 'id' => 1 }, { 'id' => 3 }])
            end

            it 'subtracts queue size from the final value' do
              is_expected.to include(max_count: chunk_query_interval / stats.average_event_time - 2)
            end
          end
        end

        context 'when average exec time is too low' do
          before do
            stats.track_exec_time { sleep 0.001 }
          end

          it 'returns the maximum acceptable value of :max_count' do
            is_expected.to include(max_count: described_class::MAX_EVENTS_PER_CHUNK)
          end

          context 'when there are events left in the queue' do
            before do
              events_processor.feed([{ 'id' => 1 }, { 'id' => 3 }])
            end

            it 'subtracts queue size from the final value' do
              is_expected.to include(max_count: described_class::MAX_EVENTS_PER_CHUNK - 2)
            end
          end
        end
      end
    end

    describe 'the result' do
      before do
        subscription.update(
          current_position: 123, options: { filter: { event_types: ['Foo'] }, resolve_link_tos: true }
        )
      end

      it 'returns query options' do
        is_expected.to(
          eq(
            filter: { event_types: ['Foo'] },
            resolve_link_tos: true,
            from_position: 124,
            max_count: described_class::INITIAL_EVENTS_PER_CHUNK
          )
        )
      end
    end
  end

  describe '#time_to_feed?' do
    subject { instance.time_to_feed? }

    context 'when it is not time to feed' do
      before do
        subscription.update(last_chunk_fed_at: Time.now.utc)
      end

      it { is_expected.to eq(false) }
    end

    context 'when it is time to feed' do
      it { is_expected.to eq(true) }
    end
  end

  describe 'processing async action' do
    subject { instance.feed([event1, event2]); sleep 0.8 }

    let(:event1) { { 'global_position' => 12, 'data' => { 'foo' => 'bar' } } }
    let(:event2) { { 'global_position' => 23, 'data' => { 'baz' => 'bar' } } }
    let(:handler) { proc { sleep 0.1 } }

    before do
      instance.start
    end

    after do
      instance.stop
    end

    it 'tracks execution time' do
      expect { subject }.to change { stats.average_event_time }.to(be_between(0.1, 0.11))
    end
    it 'updates Subscription#average_event_time' do
      expect { subject }.to change { subscription.reload.average_event_time }.to(be_between(0.1, 0.11))
    end
    it 'updates Subscription#current_position' do
      expect { subject }.to change { subscription.reload.current_position }.to(event2['global_position'])
    end
    it 'updates Subscription#events_processed_total' do
      expect { subject }.to change { subscription.reload.events_processed_total }.by(2)
    end
  end

  describe 'on error' do
    subject { instance.start; sleep 0.2 }

    let(:handler) { proc { raise 'You rolled 1. Critical failure!' } }

    before do
      instance.feed(['id' => SecureRandom.uuid, 'global_position' => 1])
    end

    after do
      instance.stop
    end

    it 'updates Subscription#last_error' do
      expect { subject }.to change {
        subscription.reload.last_error
      }.to(a_hash_including('class' => 'RuntimeError', 'message' => 'You rolled 1. Critical failure!'))
    end
    it 'updates Subscription#last_error_occurred_at' do
      expect { subject }.to change {
        subscription.reload.last_error_occurred_at
      }.to(be_between(Time.now.utc - 1, Time.now.utc + 1))
    end
    it 'restarts EventsProcessor' do
      subject
      expect(instance.state).to eq('running')
    end

    context 'when the number of restarts hit the limit' do
      before do
        subscription.update(max_restarts_number: 0)
      end

      it 'does not restart EventsProcessor' do
        subject
        expect(instance.state).to eq('dead')
      end
    end

    context 'when restart_terminator is defined' do
      let(:instance) do
        PgEventstore::SubscriptionRunner.new(
          stats: stats,
          events_processor: events_processor,
          subscription: subscription,
          restart_terminator: restart_terminator
        )
      end
      let(:restart_terminator) { proc { |sub| subscription_receiver.call(sub) } }
      let(:subscription_receiver) { double('Subscription receiver') }
      let(:terminator_result) { true }

      before do
        allow(subscription_receiver).to receive(:call).and_return(terminator_result)
      end

      it 'calls it to determine whether need to restart EventsProcessor' do
        subject
        expect(subscription_receiver).to have_received(:call).with(instance_of(PgEventstore::Subscription))
      end

      context 'when terminator returns true' do
        it 'does not restart EventsProcessor' do
          subject
          expect(instance.state).to eq('dead')
        end
      end

      context 'when terminator returns falsey value' do
        let(:terminator_result) { nil }

        it 'restarts EventsProcessor' do
          subject
          expect(instance.state).to eq('running')
        end

        context 'when the number of restarts hit the limit' do
          before do
            subscription.update(max_restarts_number: 0)
          end

          it 'does not restart EventsProcessor' do
            subject
            expect(instance.state).to eq('dead')
          end
        end
      end
    end
  end

  describe 'on restart' do
    subject { instance.start; sleep 0.2 }

    let(:handler) { proc { raise 'You rolled 1. Critical failure!' } }

    before do
      instance.feed(['id' => SecureRandom.uuid, 'global_position' => 1])
    end

    after do
      instance.stop
    end

    it 'updates Subscription#last_restarted_at' do
      expect { subject }.to change {
        subscription.reload.last_restarted_at
      }.to(be_between(Time.now.utc - 1, Time.now.utc + 1))
    end
    it 'updates Subscription#restarts_count' do
      expect { subject }.to change { subscription.reload.restarts_count }.by(1)
    end
  end

  describe 'on state changed' do
    subject { instance.start }

    after do
      instance.stop
    end

    it 'updates Subscription#state' do
      expect { subject }.to change { subscription.reload.state }.to('running')
    end
  end
end

# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionRunner do
  let(:instance) do
    described_class.new(
      stats:,
      events_processor:,
      subscription:
    )
  end
  let(:stats) { PgEventstore::SubscriptionHandlerPerformance.new }
  let(:events_processor) do
    PgEventstore::EventsProcessor.new(handler, graceful_shutdown_timeout: 5)
  end
  let(:subscription) { SubscriptionsHelper.create_with_connection(name: 'Foo') }
  let(:handler) { proc {} }

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
          subscription.update(chunk_query_interval:)
        end

        context 'when average exec time is normal' do
          before do
            stats.track_exec_time { sleep 0.2 }
            stats.track_exec_time { sleep 0.1 }
          end

          it 'calculates approximate events number of :max_count' do
            is_expected.to include(max_count: (chunk_query_interval / stats.average_event_processing_time).round)
          end

          context 'when there are events left in the queue' do
            before do
              instance.start
              dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
              events_processor.feed(
                [{ 'id' => 1, 'global_position' => 1 }, { 'id' => 3, 'global_position' => 2 }]
              )
            end

            after do
              instance.stop_async.wait_for_finish
            end

            it 'subtracts queue size from the final value' do
              is_expected.to include(max_count: (chunk_query_interval / stats.average_event_processing_time).round - 2)
            end
          end
        end

        context 'when there are a lot of events left in the chunk' do
          before do
            instance.start
            dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
            stats.track_exec_time { sleep 0.2 }
            instance.feed(Array.new(100) { |i| { 'id' => i, 'global_position' => i } })
          end

          after do
            instance.stop_async.wait_for_finish
          end

          it 'falls back to 0' do
            is_expected.to include(max_count: 0)
          end
        end

        context 'when average exec time is too fast' do
          before do
            stats.track_exec_time { sleep 0.001 }
          end

          it 'returns the maximum acceptable value of :max_count' do
            is_expected.to include(max_count: described_class::MAX_EVENTS_PER_CHUNK)
          end

          context 'when there are events left in the queue' do
            before do
              instance.start
              dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
              events_processor.feed(
                [{ 'id' => 1, 'global_position' => 1 }, { 'id' => 3, 'global_position' => 2 }]
              )
            end

            after do
              instance.stop_async.wait_for_finish
            end

            it 'subtracts queue size from the final value' do
              is_expected.to include(max_count: described_class::MAX_EVENTS_PER_CHUNK - 2)
            end
          end
        end

        context 'when average exec time is too slow' do
          let(:chunk_query_interval) { 0.5 }

          before do
            stats.track_exec_time { sleep 2 }
          end

          it 'falls back to the minimum acceptable limit' do
            is_expected.to include(max_count: described_class::MIN_EVENTS_PER_CHUNK)
          end

          context 'when there are events left in the queue' do
            before do
              instance.start
              dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
              events_processor.feed(
                [{ 'id' => 1, 'global_position' => 1 }, { 'id' => 3, 'global_position' => 2 }]
              )
            end

            after do
              instance.stop_async.wait_for_finish
            end

            it 'falls back to 0' do
              is_expected.to include(max_count: 0)
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

    context 'when #estimate_events_number is greater than zero' do
      context 'when last feed was more than Subscription#chunk_query_interval seconds ago' do
        before do
          subscription.update(last_chunk_fed_at: Time.now.utc - subscription.chunk_query_interval)
        end

        it { is_expected.to eq(true) }
      end

      context 'when last feed was less than Subscription#chunk_query_interval seconds ago' do
        before do
          subscription.update(last_chunk_fed_at: Time.now.utc)
        end

        it { is_expected.to eq(false) }
      end
    end

    context 'when #estimate_events_number is zero' do
      before do
        subscription.update(last_chunk_fed_at: Time.now.utc - subscription.chunk_query_interval)
        allow(instance).to receive(:estimate_events_number).and_return(0)
      end

      it { is_expected.to eq(false) }
    end
  end

  describe 'processing async action' do
    subject do
      instance.feed([event1, event2])
      dv.wait_until(timeout: 0.8) { subscription.reload.total_processed_events == 2 }
    end

    let(:event1) { { 'global_position' => 12, 'data' => { 'foo' => 'bar' } } }
    let(:event2) { { 'global_position' => 23, 'data' => { 'baz' => 'bar' } } }
    let(:handler) { proc { sleep 0.1 } }

    before do
      instance.start
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'tracks execution time' do
      expect { subject }.to change { stats.average_event_processing_time }.to(be_between(0.1, 0.11))
    end
    it 'updates Subscription#average_event_processing_time' do
      expect { subject }.to change { subscription.reload.average_event_processing_time }.to(be_between(0.1, 0.11))
    end
    it 'updates Subscription#current_position' do
      expect { subject }.to change { subscription.reload.current_position }.to(event2['global_position'])
    end
    it 'updates Subscription#total_processed_events' do
      expect { subject }.to change { subscription.reload.total_processed_events }.by(2)
    end
  end

  describe 'on error' do
    subject do
      instance.feed([event])
      dv(processed_events).wait_until(timeout: 0.6) { _1.size == 1 }
    end

    let(:handler) do
      should_raise = true
      error = self.error
      proc do |event|
        if should_raise
          should_raise = false
          raise error
        end
        processed_events.push(event)
      end
    end
    let(:error) { StandardError.new('You rolled 1. Critical failure!') }
    let(:processed_events) { [] }
    let(:event) { { 'id' => SecureRandom.uuid, 'global_position' => 1 } }
    let(:subscription) { SubscriptionsHelper.create_with_connection(name: 'Foo', time_between_restarts: 0) }

    before do
      instance.start
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'updates Subscription#last_error' do
      expect { subject }.to change {
        subscription.reload.last_error
      }.to(a_hash_including('class' => 'StandardError', 'message' => 'You rolled 1. Critical failure!'))
    end
    it 'updates Subscription#last_error_occurred_at' do
      expect { subject }.to change {
        subscription.reload.last_error_occurred_at
      }.to(be_between(Time.now.utc - 1, Time.now.utc + 1))
    end
  end

  describe 'on restart' do
    subject do
      instance.feed(['id' => SecureRandom.uuid, 'global_position' => 1])
      dv.wait_until(timeout: 1) { subscription.reload.restart_count > 0 }
    end

    let(:handler) { proc { raise 'You rolled 1. Critical failure!' } }
    let(:subscription) { SubscriptionsHelper.create_with_connection(name: 'Foo') }

    let(:events_processor) do
      PgEventstore::EventsProcessor.new(
        handler,
        graceful_shutdown_timeout: 0,
        recovery_strategies: [
          DummyErrorRecovery.new(recoverable_message: 'You rolled 1. Critical failure!', seconds_before_recovery: 0.1),
        ]
      )
    end

    before do
      instance.start
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
    end

    after do
      instance.stop_async.wait_for_finish
    end

    it 'updates Subscription#last_restarted_at' do
      expect { subject }.to change {
        subscription.reload.last_restarted_at
      }.to(be_between(Time.now.utc - 1, Time.now.utc + 1))
    end
    it 'updates Subscription#restart_count' do
      expect { subject }.to change { subscription.reload.restart_count }
    end
  end

  describe 'on state changed' do
    subject { instance.start }

    after do
      instance.stop_async.wait_for_finish
    end

    it 'updates Subscription#state' do
      expect { subject }.to change { subscription.reload.state }.to('running')
    end
  end

  describe 'on fed' do
    subject { instance.feed(raw_events) }

    let(:raw_events) { [{ 'global_position' => 2 }, { 'global_position' => 3 }] }

    before do
      subscription.update(last_chunk_greatest_position: 1)
      instance.start
      dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
    end

    after do
      instance.stop_async.wait_for_finish
    end

    context 'when events are present' do
      it 'updates subscription#last_chunk_fed_at' do
        expect { subject }.to change {
          subscription.reload.last_chunk_fed_at
        }.to(be_between(Time.now.utc, Time.now.utc + 1))
      end
      it 'updates subscription#last_chunk_greatest_position' do
        expect { subject }.to change { subscription.reload.last_chunk_greatest_position }.to(3)
      end
    end

    context 'when events are empty' do
      let(:raw_events) { [] }

      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::EmptyChunkFedError)
      end
    end
  end
end

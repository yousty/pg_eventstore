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
    PgEventstore::EventsProcessor.new(
      consumer: PgEventstore::EventsProcessorConsumer::Single.new(handler),
      graceful_shutdown_timeout: 5,
      recovery_strategies:
    )
  end
  let(:subscription) { SubscriptionsHelper.create_with_connection(name: 'Foo') }
  let(:handler) { proc {} }
  let(:recovery_strategies) { [] }
  let(:graceful_shutdown_timeout) { 5 }

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
            let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
            let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new }) }
            let(:indexes) { prepare_subscription_indexes(events) }
            let(:chunk) { create_subscription_index_chunk(indexes) }

            before do
              instance.start
              dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
              events_processor.feed(chunk)
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
          let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
          let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(100) { PgEventstore::Event.new }) }
          let(:indexes) { prepare_subscription_indexes(events) }
          let(:chunk) { create_subscription_index_chunk(indexes) }

          before do
            instance.start
            dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
            stats.track_exec_time { sleep 0.2 }
            instance.feed(chunk)
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
            let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
            let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new }) }
            let(:indexes) { prepare_subscription_indexes(events) }
            let(:chunk) { create_subscription_index_chunk(indexes) }

            before do
              instance.start
              dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
              events_processor.feed(chunk)
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
            let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
            let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new }) }
            let(:indexes) { prepare_subscription_indexes(events) }
            let(:chunk) { create_subscription_index_chunk(indexes) }

            before do
              instance.start
              dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
              events_processor.feed(chunk)
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

    describe ':resolve_link_tos' do
      subject { super()[:resolve_link_tos] }

      context 'when subscription does not define :resolve_link_tos option' do
        it { is_expected.to eq(false) }
      end

      context 'when subscription defines :resolve_link_tos option' do
        before do
          subscription.update(options: { resolve_link_tos: true })
        end

        it { is_expected.to eq(true) }
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
      instance.feed(chunk)
      dv.wait_until(timeout: 0.8) { subscription.reload.total_processed_events == 2 }
    end

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new }) }
    let(:indexes) { prepare_subscription_indexes(events) }
    let(:chunk) { create_subscription_index_chunk(indexes) }
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
      expect { subject }.to change { subscription.reload.current_position }.to(indexes.last.subscription_position)
    end
    it 'updates Subscription#total_processed_events' do
      expect { subject }.to change { subscription.reload.total_processed_events }.by(2)
    end
  end

  describe 'on error' do
    subject do
      instance.feed(chunk)
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
    let(:subscription) { SubscriptionsHelper.create_with_connection(name: 'Foo', time_between_restarts: 0) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(1) { PgEventstore::Event.new }) }
    let(:indexes) { prepare_subscription_indexes(events) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

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
      instance.feed(chunk)
      dv.wait_until(timeout: 1) { subscription.reload.restart_count > 0 }
    end

    let(:handler) { proc { raise 'You rolled 1. Critical failure!' } }
    let(:subscription) { SubscriptionsHelper.create_with_connection(name: 'Foo') }

    let(:recovery_strategies) do
      [DummyErrorRecovery.new(recoverable_message: 'You rolled 1. Critical failure!', seconds_before_recovery: 0.1)]
    end
    let(:graceful_shutdown_timeout) { 0 }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new }) }
    let(:indexes) { prepare_subscription_indexes(events) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

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
    subject { instance.feed(chunk) }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new }) }
    let(:indexes) { prepare_subscription_indexes(events) }
    let(:chunk) { create_subscription_index_chunk(indexes) }

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
        expect { subject }.to change {
          subscription.reload.last_chunk_greatest_position
        }.to(indexes.last.subscription_position)
      end
    end

    context 'when events are empty' do
      let(:indexes) { [] }

      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::EmptyChunkFedError)
      end
    end
  end

  describe 'on checkpoint' do
    subject do
      instance.feed(checkpoint_chunk)
      dv(instance).wait_until(timeout: 0.2) { _1.subscription.current_position == position }
    end

    let(:position) { 123 }
    let(:checkpoint_chunk) { PgEventstore::Chunks::SubscriptionCheckpointChunk.new(position) }

    before do
      stub_const('PgEventstore::EventsProcessorConsumer::Single::EVENT_WAIT_TIMEOUT', 0.1)
    end

    context 'when instance is running' do
      before do
        instance.start
        dv(instance).wait_until(timeout: 0.1) { _1.state == 'running' }
      end

      after do
        instance.stop_async.wait_for_finish
      end

      context 'when there are currently no events to process' do
        it 'updates Subscription#current_position' do
          expect { subject }.to change { subscription.reload.current_position }.to(position)
        end
        it 'updates Subscription#last_chunk_greatest_position' do
          expect { subject }.to change { subscription.reload.last_chunk_greatest_position }.to(position)
        end
      end

      context 'when there are events to process' do
        let(:handler) do
          processed_positions = self.processed_positions
          proc { processed_positions.push(_1['global_position']) }
        end
        let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
        let(:events) { PgEventstore.client.append_to_stream(stream, Array.new(2) { PgEventstore::Event.new }) }
        let(:indexes) { prepare_subscription_indexes(events) }
        let(:chunk) { create_subscription_index_chunk(indexes) }

        let(:processed_positions) { [] }

        before do
          instance.feed(chunk)
        end

        it 'updates Subscription#current_position to checkpoint' do
          expect { subject }.to change { subscription.reload.current_position }.to(position)
        end
        it 'updates Subscription#last_chunk_greatest_position to checkpoint' do
          expect { subject }.to change { subscription.reload.last_chunk_greatest_position }.to(position)
        end
        it 'does not process checkpoint event' do
          expect { subject }.to change { processed_positions }.to(events.map(&:global_position))
        end
      end

      context 'when subscription is already at the given checkpoint' do
        before do
          subscription.update(current_position: position, last_chunk_greatest_position: position)
        end

        it 'does not update the subscription' do
          expect { subject }.not_to change { subscription.reload.updated_at }
        end
      end
    end

    context 'when instance is not running' do
      it 'does not update Subscription#current_position' do
        expect { subject }.not_to change { subscription.reload.current_position }
      end
      it 'does not update Subscription#last_chunk_greatest_position' do
        expect { subject }.not_to change { subscription.reload.last_chunk_greatest_position }
      end
    end
  end
end

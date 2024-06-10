# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionRunnersFeeder do
  let(:instance) { described_class.new(config_name) }
  let(:config_name) { :default }

  describe '#feed' do
    subject { instance.feed([runner1, runner2]) }

    let(:runner1) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Foo', options: options1)
      )
    end
    let(:runner2) do
      PgEventstore::SubscriptionRunner.new(
        stats: PgEventstore::SubscriptionHandlerPerformance.new,
        events_processor: PgEventstore::EventsProcessor.new(proc { }),
        subscription: SubscriptionsHelper.create_with_connection(name: 'Bar', options: options2)
      )
    end
    let(:options1) { { filter: { event_types: ['Foo'] } } }
    let(:options2) { { filter: { streams: [{ context: 'FooCtx' }] } } }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: 'bar') }
    let(:event1) { PgEventstore::Event.new(data: { foo: :bar }, type: 'Foo') }
    let(:event2) { PgEventstore::Event.new(data: { bar: :baz }, type: 'Bar') }


    before do
      allow(runner1).to receive(:feed).and_call_original
      allow(runner2).to receive(:feed).and_call_original
      PgEventstore.client.append_to_stream(stream, [event1, event2])
      runner1.start
      runner2.start
    end

    after do
      [runner1, runner2].each(&:stop_async).each(&:wait_for_finish)
    end

    it 'feeds first runner with corresponding events' do
      subject
      expect(runner1).to have_received(:feed).with([a_hash_including('type' => 'Foo')])
    end
    it 'feeds second runner with corresponding events' do
      subject
      expect(runner2).to(
        have_received(:feed).with([a_hash_including('type' => 'Foo'), a_hash_including('type' => 'Bar')])
      )
    end

    shared_examples 'does not feed first runner, feeds second runner' do
      it 'does not feed first runner' do
        subject
        expect(runner1).not_to have_received(:feed)
      end
      it 'feeds second runner' do
        subject
        expect(runner2).to(
          have_received(:feed).with([a_hash_including('type' => 'Foo'), a_hash_including('type' => 'Bar')])
        )
      end
    end

    context 'when first runner is not running' do
      before do
        runner1.stop_async.wait_for_finish
      end

      it_behaves_like 'does not feed first runner, feeds second runner'
    end

    context 'when first runner has already been fed' do
      before do
        runner1.subscription.update(last_chunk_fed_at: Time.now.utc)
      end

      it_behaves_like 'does not feed first runner, feeds second runner'
    end

    context 'when first runner does not have corresponding events' do
      let(:options1) { { filter: { event_types: ['Baz'] } } }

      it 'does not feed first runner' do
        subject
        expect(runner1).not_to have_received(:feed)
      end
      it 'feeds second runner' do
        subject
        expect(runner2).to(
          have_received(:feed).with([a_hash_including('type' => 'Foo'), a_hash_including('type' => 'Bar')])
        )
      end
    end
  end
end

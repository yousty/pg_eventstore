# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Paginator::EventsCollection do
  let(:instance) do
    described_class.new(
      config_name,
      starting_id: starting_id,
      per_page: per_page,
      order: order,
      options: options,
      system_stream: system_stream
    )
  end
  let(:config_name) { :default }
  let(:starting_id) { nil }
  let(:per_page) { 2 }
  let(:order) { :asc }
  let(:options) { {} }
  let(:system_stream) { nil }

  describe '#collection' do
    subject { instance.collection }

    let!(:event1) do
      event = PgEventstore::Event.new(type: 'Foo')
      PgEventstore.client.append_to_stream(stream1, event)
    end
    let!(:event2) do
      event = PgEventstore::Event.new(type: 'Bar')
      PgEventstore.client.append_to_stream(stream1, event)
    end
    let!(:event3) do
      event = PgEventstore::Event.new(type: 'Foo')
      PgEventstore.client.append_to_stream(stream2, event)
    end
    let!(:event4) do
      event = PgEventstore::Event.new(type: 'Bar')
      PgEventstore.client.append_to_stream(stream3, event)
    end
    let!(:event5) do
      event = PgEventstore::Event.new(type: 'Baz')
      PgEventstore.client.append_to_stream(stream3, event)
    end

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '2') }
    let(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'MyStream', stream_id: '1') }

    it 'returns events according to the page limit and in the given order' do
      is_expected.to eq([event1, event2])
    end

    context 'when starting_id is given' do
      let(:starting_id) { event3.global_position }

      it 'returns events starting from that id' do
        is_expected.to eq([event3, event4])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns events starting from that id, properly ordered' do
          is_expected.to eq([event3, event2])
        end
      end

      context 'when filtering by event type' do
        let(:options) { { filter: { event_types: ['Foo'] } } }

        it 'returns events by that type, starting from the given id' do
          is_expected.to eq([event3])
        end
      end

      context 'when filtering by stream parts' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }] } } }

        it 'returns events by that context, starting from the given id' do
          is_expected.to eq([event3])
        end
      end
    end

    context 'when reading a link event' do
      let!(:link) { PgEventstore.client.link_to(stream3, event1) }
      let(:order) { :desc }

      it 'returns it' do
        is_expected.to eq([link, event5])
      end

      context 'when :resolve_link_tos option is provided' do
        let(:options) { { resolve_link_tos: true } }

        it 'resolves the link' do
          is_expected.to eq([event1, event5])
        end
      end
    end

    context 'when middleware is registered' do
      before do
        PgEventstore.configure do |c|
          c.middlewares = { dummy: DummyMiddleware.new }
        end
      end

      after do
        PgEventstore.configure do |c|
          c.middlewares = {}
        end
      end

      it 'recognizes it' do
        aggregate_failures do
          expect(subject.size).to eq(2)
          is_expected.to all satisfy { |event| event.metadata == { DummyMiddleware::STORAGE_KEY => DummyMiddleware::DECR_SECRET } }
        end
      end
    end

    context 'when reading from "$streams" system stream' do
      let(:system_stream) { '$streams' }

      it 'returns 0-stream revision events according to the page limit and in the given order' do
        is_expected.to eq([event1, event3])
      end
    end
  end

  describe '#next_page_starting_id' do
    subject { instance.next_page_starting_id }

    let!(:event1) do
      event = PgEventstore::Event.new(type: 'Foo')
      PgEventstore.client.append_to_stream(stream1, event)
    end
    let!(:event2) do
      event = PgEventstore::Event.new(type: 'Bar')
      PgEventstore.client.append_to_stream(stream1, event)
    end
    let!(:event3) do
      event = PgEventstore::Event.new(type: 'Foo')
      PgEventstore.client.append_to_stream(stream2, event)
    end
    let!(:event4) do
      event = PgEventstore::Event.new(type: 'Bar')
      PgEventstore.client.append_to_stream(stream3, event)
    end
    let!(:event5) do
      event = PgEventstore::Event.new(type: 'Baz')
      PgEventstore.client.append_to_stream(stream3, event)
    end

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '2') }
    let(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'MyStream', stream_id: '1') }

    it 'returns next page id according to the page limit and in the given order' do
      is_expected.to eq(event3.global_position)
    end

    context 'when starting_id is given' do
      let(:starting_id) { event3.global_position }

      it 'returns next page id relative to the starting_id' do
        is_expected.to eq(event5.global_position)
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns next page id relative to the starting_id according to the given order' do
          is_expected.to eq(event1.global_position)
        end
      end

      context 'when filtering by event type' do
        let(:options) { { filter: { event_types: ['Foo'] } } }

        let!(:foo_event1) do
          event = PgEventstore::Event.new(type: 'Foo')
          PgEventstore.client.append_to_stream(stream3, event)
        end
        let!(:foo_event2) do
          event = PgEventstore::Event.new(type: 'Foo')
          PgEventstore.client.append_to_stream(stream3, event)
        end

        it 'returns next page id relative to the starting_id, according to the given event type filter' do
          is_expected.to eq(foo_event2.global_position)
        end
      end

      context 'when filtering by stream parts' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }] } } }

        let!(:foo_event1) do
          event = PgEventstore::Event.new(type: 'Baz')
          PgEventstore.client.append_to_stream(stream1, event)
        end
        let!(:foo_event2) do
          event = PgEventstore::Event.new(type: 'Bar')
          PgEventstore.client.append_to_stream(stream2, event)
        end

        it 'returns next page id by that context, starting from the given id' do
          is_expected.to eq(foo_event2.global_position)
        end
      end
    end

    describe 'resolving next page id from link event' do
      let!(:link) { PgEventstore.client.link_to(stream3, event1) }

      let(:starting_id) { event4.global_position }

      it 'picks #global_position of a link event' do
        aggregate_failures do
          is_expected.to eq(link.global_position)
          is_expected.not_to eq(event1.global_position)
        end
      end
    end

    context 'when next page does not exist' do
      let(:starting_id) { event4.global_position }

      it { is_expected.to eq(nil) }
    end

    context 'when reading from "$streams" system stream' do
      let(:system_stream) { '$streams' }

      it 'returns next page id for 0-stream revision events according to the page limit and in the given order' do
        is_expected.to eq(event4.global_position)
      end
    end
  end

  describe '#prev_page_starting_id' do
    subject { instance.prev_page_starting_id }

    let!(:event1) do
      event = PgEventstore::Event.new(type: 'Foo')
      PgEventstore.client.append_to_stream(stream1, event)
    end
    let!(:event2) do
      event = PgEventstore::Event.new(type: 'Bar')
      PgEventstore.client.append_to_stream(stream1, event)
    end
    let!(:event3) do
      event = PgEventstore::Event.new(type: 'Foo')
      PgEventstore.client.append_to_stream(stream2, event)
    end
    let!(:event4) do
      event = PgEventstore::Event.new(type: 'Bar')
      PgEventstore.client.append_to_stream(stream3, event)
    end
    let!(:event5) do
      event = PgEventstore::Event.new(type: 'Baz')
      PgEventstore.client.append_to_stream(stream3, event)
    end

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '2') }
    let(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'MyStream', stream_id: '1') }

    context 'when starting_id is given' do
      let(:starting_id) { event3.global_position }

      it 'returns prev page id relative to the starting_id' do
        is_expected.to eq(event1.global_position)
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns prev page id relative to the starting_id according to the given order' do
          is_expected.to eq(event5.global_position)
        end
      end

      context 'when filtering by event type' do
        let(:options) { { filter: { event_types: ['Foo'] } } }
        let(:starting_id) { foo_event2.global_position }

        let!(:foo_event1) do
          event = PgEventstore::Event.new(type: 'Foo')
          PgEventstore.client.append_to_stream(stream3, event)
        end
        let!(:foo_event2) do
          event = PgEventstore::Event.new(type: 'Foo')
          PgEventstore.client.append_to_stream(stream3, event)
        end

        it 'returns prev page id relative to the starting_id, according to the given event type filter' do
          is_expected.to eq(event3.global_position)
        end
      end

      context 'when filtering by stream parts' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }] } } }
        let(:starting_id) { foo_event2.global_position }

        let!(:foo_event1) do
          event = PgEventstore::Event.new(type: 'Baz')
          PgEventstore.client.append_to_stream(stream1, event)
        end
        let!(:foo_event2) do
          event = PgEventstore::Event.new(type: 'Bar')
          PgEventstore.client.append_to_stream(stream2, event)
        end

        it 'returns prev page id by that context, starting from the given id' do
          is_expected.to eq(event3.global_position)
        end
      end

      context 'when reading from "$streams" system stream' do
        let(:system_stream) { '$streams' }
        let(:starting_id) { event4.global_position }

        it 'returns prev page id for 0-stream revision events relative to the starting_id' do
          is_expected.to eq(event1.global_position)
        end
      end
    end

    describe 'resolving prev page id from link event' do
      let!(:link) { PgEventstore.client.link_to(stream3, event1) }
      let(:starting_id) { event4.global_position }
      let(:order) { :desc }

      it 'picks #global_position of a link event' do
        aggregate_failures do
          is_expected.to eq(link.global_position)
          is_expected.not_to eq(event1.global_position)
        end
      end
    end

    context 'when prev page contains less events than per_page number' do
      let(:starting_id) { event4.global_position }
      let(:order) { :desc }

      it 'picks global_position correctly' do
        is_expected.to eq(event5.global_position)
      end
    end

    context 'when prev page does not exist' do
      it { is_expected.to eq(nil) }
    end
  end

  describe '#total_count' do
    subject { instance.total_count }

    describe '"all" stream' do
      context 'when number of records does not exceed the limit' do
        before do
          events = [PgEventstore::Event.new(type: 'Foo')] * 5
          PgEventstore.client.append_to_stream(
            PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1'),
            events
          )
        end

        it 'returns events count' do
          is_expected.to eq(5)
        end
      end

      context 'when number of records exceeds the limit' do
        before do
          stub_const("#{described_class}::MAX_NUMBER_TO_COUNT", 2)
          events = [PgEventstore::Event.new(type: 'Foo')] * 5
          PgEventstore.client.append_to_stream(
            PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: '1'),
            events
          )
        end

        it 'returns estimate count' do
          is_expected.to be_between(5, 1000)
        end
      end
    end

    describe '"$streams" system stream' do
      let(:system_stream) { '$streams' }

      context 'when number of records does not exceed the limit' do
        before do
          5.times do |t|
            event = PgEventstore::Event.new(type: 'Foo')
            stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: t.to_s)
            PgEventstore.client.append_to_stream(stream, event)
          end
        end

        it 'returns events count' do
          is_expected.to eq(5)
        end
      end

      context 'when number of records exceeds the limit' do
        before do
          stub_const("#{described_class}::MAX_NUMBER_TO_COUNT", 2)
          5.times do |t|
            event = PgEventstore::Event.new(type: 'Foo')
            stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: t.to_s)
            PgEventstore.client.append_to_stream(stream, event)
          end
        end

        it 'returns estimate count' do
          is_expected.to be_between(5, 1000)
        end
      end
    end
  end
end

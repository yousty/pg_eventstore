# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::Read do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(
      index_filtering: index_filtering_queries,
      streams_global_index: streams_global_index_queries
    )
  end
  let(:index_filtering_queries) { PgEventstore::IndexFilteringQueries.new(PgEventstore.connection, query_strategy) }
  let(:streams_global_index_queries) do
    PgEventstore::StreamsGlobalIndexQueries.new(PgEventstore.connection, query_strategy)
  end
  let(:query_strategy) { PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection) }
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }
  let(:deserializer) { PgEventstore::EventDeserializer.new(middlewares, event_class_resolver) }

  describe '#call' do
    subject { instance.call(stream, deserializer:, options:) }

    let(:options) { {} }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream2', stream_id: '1234')
    end
    let(:stream) { events_stream1 }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }

    before do
      PgEventstore.client.append_to_stream(events_stream1, [event1, event2, event3])
      PgEventstore.client.append_to_stream(events_stream2, event4)
    end

    context 'when no options are given' do
      it 'returns events' do
        expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
      end
    end

    context 'when :max_count option is given' do
      let(:options) { { max_count: 2 } }

      it 'limits number of the events in the result' do
        expect(subject.map(&:id)).to eq([event1.id, event2.id])
      end
    end

    describe 'reading links' do
      let(:existing_event) { PgEventstore.client.read(events_stream2).first }
      let(:projection_stream) do
        PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyProjection', stream_id: '1')
      end
      let!(:link) do
        PgEventstore.client.link_to(projection_stream, existing_event)
      end
      let(:stream) { projection_stream }

      context 'when :resolve_link_tos is not provided' do
        it 'returns links as is' do
          expect(subject).to eq([link])
        end
      end

      context 'when :resolve_link_tos is provided' do
        let(:options) { { resolve_link_tos: true } }

        it 'resolves links to original events' do
          aggregate_failures do
            expect(subject).to eq([existing_event])
            expect(subject.first.stream).to eq(events_stream2)
            expect(subject.first.type).to eq('baz')
            expect(subject.first.link).to eq(link)
          end
        end
      end
    end

    describe 'reading last event in the regular stream' do
      let(:options) { { max_count: 1, direction: 'Backwards' } }

      it 'returns last event of the stream' do
        expect(subject.map(&:id)).to eq([event3.id])
      end
    end

    describe 'reading last event in "all" stream' do
      let(:stream) { PgEventstore::Stream.all_stream }
      let(:options) { { max_count: 1, direction: 'Backwards' } }

      it 'returns last event of the stream' do
        expect(subject.map(&:id)).to eq([event4.id])
      end
    end

    describe 'reading from "all" stream when no events match the filter' do
      let(:stream) { PgEventstore::Stream.all_stream }
      let(:options) { { filter: { event_types: ['NonExisting'] } } }

      it { is_expected.to eq([]) }
    end

    describe 'reading from the specific stream when no events match the filter' do
      let(:options) { { filter: { event_types: ['NonExisting'] } } }

      it { is_expected.to eq([]) }
    end

    describe 'reading from "all" stream with mix of existing and non-existing events' do
      let(:stream) { PgEventstore::Stream.all_stream }
      let(:options) { { filter: { event_types: %w[NonExisting baz] } } }

      it 'returns matching events' do
        expect(subject.map(&:id)).to eq([event3.id, event4.id])
      end
    end

    describe 'reading from specific stream with mix of existing and non-existing events' do
      let(:options) { { filter: { event_types: %w[NonExisting foo] } } }

      it 'returns matching events' do
        expect(subject.map(&:id)).to eq([event1.id])
      end
    end

    describe 'reading from the non-existing, specified stream' do
      let(:stream) { PgEventstore::Stream.new(context: 'Foo', stream_name: 'Bar', stream_id: 'baz') }

      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::StreamNotFoundError)
      end
    end

    context 'when middleware is present' do
      let(:middlewares) { [DummyMiddleware.new] }

      it 'modifies the event using it' do
        expect(subject.first.metadata).to eq('dummy_secret' => DummyMiddleware::DECR_SECRET)
      end
    end

    context 'when a middleware has default Middleware module implementation' do
      let(:middlewares) { [dummy_middleware.new] }
      let(:dummy_middleware) do
        Class.new.tap { |c| c.include(PgEventstore::Middleware) }
      end

      it 'does not modify the event' do
        expect(subject.first.metadata).to eq({})
      end
    end
  end

  describe 'resolve event class when reading from stream' do
    subject { instance.call(stream, deserializer:, options:) }

    let(:event_class) { Class.new(PgEventstore::Event) }
    let(:event) { event_class.new }
    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }
    let(:options) { {} }

    before do
      stub_const('DummyClass', event_class)
      PgEventstore.client.append_to_stream(stream, event)
    end

    it "recognizes event's class" do
      expect(subject.first).to be_a(DummyClass)
    end

    context 'when :resolve_link_tos option is given' do
      let(:options) { { resolve_link_tos: true } }

      it "recognizes event's class" do
        expect(subject.first).to be_a(DummyClass)
      end
    end
  end

  describe 'reading using filter by stream parts' do
    subject { instance.call(stream, deserializer:, options:) }

    let(:options) { {} }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream1', stream_id: '12345')
    end
    let(:events_stream3) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream2', stream_id: '1234')
    end
    let(:events_stream4) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext2', stream_name: 'some-stream3', stream_id: '1234')
    end
    let(:events_stream5) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream1', stream_id: '1235')
    end

    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }

    let(:event6) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
    let(:event7) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event8) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }
    let(:event9) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event10) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }

    let(:stream) { events_stream1 }

    before do
      PgEventstore.client.append_to_stream(events_stream1, [event1, event6])
      PgEventstore.client.append_to_stream(events_stream2, [event2, event7])
      PgEventstore.client.append_to_stream(events_stream3, [event3, event8])
      PgEventstore.client.append_to_stream(events_stream4, [event4, event9])
      PgEventstore.client.append_to_stream(events_stream5, [event5, event10])
    end

    describe 'filtering by the context' do
      let(:options) { { filter: { streams: [{ context: 'SomeContext' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given context' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id, event3.id, event8.id])
        end
      end
    end

    describe 'filtering by the stream name only' do
      let(:options) { { filter: { streams: [{ stream_name: 'some-stream1' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'ignores it, returning all events' do
          expect(subject.map(&:id)).to(
            eq(
              [
                event1.id, event6.id,
                event2.id, event7.id,
                event3.id, event8.id,
                event4.id, event9.id,
                event5.id, event10.id
              ]
            )
          )
        end
      end
    end

    describe 'filtering by two different contexts' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext' }, { context: 'SomeAnotherContext2' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given contexts' do
          expect(subject.map(&:id)).to eq([event2.id, event7.id, event4.id, event9.id, event5.id, event10.id])
        end
      end
    end

    describe 'filtering by stream name and context as a part of the same filter' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext', stream_name: 'some-stream1' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given stream name and context' do
          expect(subject.map(&:id)).to eq([event2.id, event7.id, event5.id, event10.id])
        end
      end
    end

    describe 'filtering by several stream names and contexts' do
      let(:options) do
        {
          filter: {
            streams: [
              { context: 'SomeAnotherContext', stream_name: 'some-stream1' },
              { context: 'SomeContext', stream_name: 'some-stream1' },
            ],
          },
        }
      end

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given stream names and contexts' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id, event2.id, event7.id, event5.id, event10.id])
        end
      end
    end

    describe 'filtering by stream name and context as a part of different streams' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext' }, { stream_name: 'some-stream1' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events that match context only, ignoring stream_name' do
          expect(subject.map(&:id)).to eq([event2.id, event7.id, event5.id, event10.id])
        end
      end
    end

    describe 'filtering by several specific streams' do
      let(:options) { { filter: { streams: [events_stream1.to_hash, events_stream4.to_hash] } } }

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events of those streams' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id, event4.id, event9.id])
        end
      end
    end

    describe 'filtering by the stream id only' do
      let(:options) { { filter: { streams: [{ stream_id: '1234' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'ignores it, returning all events' do
          expect(subject.map(&:id)).to(
            eq(
              [
                event1.id, event6.id,
                event2.id, event7.id,
                event3.id, event8.id,
                event4.id, event9.id,
                event5.id, event10.id
              ]
            )
          )
        end
      end
    end

    describe 'filtering by context and stream id as a part of different filters' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext2' }, { stream_id: '123' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events that match the given context only, ignoring stream id' do
          expect(subject.map(&:id)).to eq([event4.id, event9.id])
        end
      end
    end

    describe 'filtering by stream name and stream id as a part of different filters' do
      let(:options) { { filter: { streams: [{ stream_name: 'some-stream3' }, { stream_id: '1234' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it, returning events of the given stream' do
          expect(subject.map(&:id)).to eq([event1.id, event6.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'ignores it, returning all events' do
          expect(subject.map(&:id)).to(
            eq(
              [
                event1.id, event6.id,
                event2.id, event7.id,
                event3.id, event8.id,
                event4.id, event9.id,
                event5.id, event10.id
              ]
            )
          )
        end
      end
    end
  end

  describe 'reading using filter by event type' do
    subject { instance.call(stream, deserializer:, options:) }

    let(:options) { { filter: { event_types: %w[foo baz] } } }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream2', stream_id: '123')
    end
    let(:stream) { events_stream1 }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }

    before do
      PgEventstore.client.append_to_stream(events_stream1, [event1, event2])
      PgEventstore.client.append_to_stream(events_stream2, [event3, event4, event5])
    end

    context 'when reading from specific stream' do
      it 'returns events according to the given types in the given stream' do
        expect(subject.map(&:id)).to eq([event1.id])
      end
    end

    context 'when reading from "all" stream' do
      let(:stream) { PgEventstore::Stream.all_stream }

      it 'returns events according to the given types' do
        expect(subject.map(&:id)).to eq([event1.id, event3.id, event5.id])
      end
    end
  end

  describe 'reading using filter by event type and by stream parts' do
    subject { instance.call(stream, deserializer:, options:) }

    let(:options) do
      { filter: { event_types: %w[foo baz], streams: [{ context: 'SomeContext', stream_name: 'some-stream1' }] } }
    end
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream2', stream_id: '123')
    end
    let(:events_stream3) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '124')
    end
    let(:stream) { events_stream1 }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
    let(:event6) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }

    before do
      PgEventstore.client.append_to_stream(events_stream1, [event1, event2])
      PgEventstore.client.append_to_stream(events_stream2, [event3, event4])
      PgEventstore.client.append_to_stream(events_stream3, [event5, event6])
    end

    context 'when reading from regular stream' do
      it 'filters events only by the given types' do
        expect(subject.map(&:id)).to eq([event1.id])
      end
    end

    context 'when reading from "all" stream' do
      let(:stream) { PgEventstore::Stream.all_stream }

      it 'filters events by the given event types and by the given stream parts' do
        expect(subject.map(&:id)).to eq([event1.id, event5.id, event6.id])
      end
    end
  end

  describe 'direction of reading from/to position/revision' do
    subject { instance.call(stream, deserializer:, options:) }

    let(:options) { {} }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream2', stream_id: '123')
    end
    let(:events_stream3) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream3', stream_id: '123')
    end

    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'baz') }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'bar') }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }
    let(:event6) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'foo') }

    let(:stream) { events_stream2 }

    before do
      PgEventstore.client.append_to_stream(events_stream1, [event1, event2])
      PgEventstore.client.append_to_stream(events_stream2, [event3, event4, event5])
      PgEventstore.client.append_to_stream(events_stream3, event6)
    end

    context 'when reading from a specific stream' do
      shared_examples 'historical events order' do
        it 'reads events in historical order' do
          expect(subject.map(&:id)).to eq([event3.id, event4.id, event5.id])
        end

        context 'when :from_revision option is provided' do
          let(:options) { super().merge(from_revision: 1) }

          it 'reads events in historical order from the specific revision' do
            expect(subject.map(&:id)).to eq([event4.id, event5.id])
          end
        end

        context 'when :to_revision option is provided' do
          let(:options) { super().merge(to_revision: 1) }

          it 'reads events in historical order to the specific revision' do
            expect(subject.map(&:id)).to eq([event3.id, event4.id])
          end
        end
      end

      shared_examples 'reversed events order' do
        it 'reads events from old to new ordering' do
          expect(subject.map(&:id)).to eq([event5.id, event4.id, event3.id])
        end

        context 'when :from_revision option is provided' do
          let(:options) { super().merge(from_revision: 1) }

          it 'reads events from old to new ordering from the specific revision' do
            expect(subject.map(&:id)).to eq([event4.id, event3.id])
          end
        end

        context 'when :to_revision option is provided' do
          let(:options) { super().merge(to_revision: 1) }

          it 'reads events from old to new ordering to the specific revision' do
            expect(subject.map(&:id)).to eq([event5.id, event4.id])
          end
        end
      end

      context 'when no direction is given' do
        it_behaves_like 'historical events order'
      end

      context 'when direction is "Forwards"' do
        let(:options) { { direction: 'Forwards' } }

        it_behaves_like 'historical events order'
      end

      context 'when direction is "asc"' do
        let(:options) { { direction: 'asc' } }

        it_behaves_like 'historical events order'
      end

      context 'when direction is :asc' do
        let(:options) { { direction: :asc } }

        it_behaves_like 'historical events order'
      end

      context 'when direction is "Backwards"' do
        let(:options) { { direction: 'Backwards' } }

        it_behaves_like 'reversed events order'
      end

      context 'when direction is "desc"' do
        let(:options) { { direction: 'desc' } }

        it_behaves_like 'reversed events order'
      end

      context 'when direction is :desc' do
        let(:options) { { direction: :desc } }

        it_behaves_like 'reversed events order'
      end
    end

    context 'when reading from "all" stream' do
      let(:stream) { PgEventstore::Stream.all_stream }

      shared_examples 'historical events order' do
        it 'reads events in historical order' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id, event4.id, event5.id, event6.id])
        end

        context 'when :from_position option is provided' do
          let(:options) { super().merge(from_position: PgEventstore.client.read(stream)[2].global_position) }

          it 'reads events in historical order from the specific position' do
            expect(subject.map(&:id)).to eq([event3.id, event4.id, event5.id, event6.id])
          end
        end

        context 'when :to_position option is provided' do
          let(:options) { super().merge(to_position: PgEventstore.client.read(stream)[2].global_position) }

          it 'reads events in historical order to the specific position' do
            expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
          end
        end
      end

      shared_examples 'reversed events order' do
        it 'reads events from old to new ordering' do
          expect(subject.map(&:id)).to eq([event6.id, event5.id, event4.id, event3.id, event2.id, event1.id])
        end

        context 'when :from_position option is provided' do
          let(:options) { super().merge(from_position: PgEventstore.client.read(stream)[2].global_position) }

          it 'reads events from old to new ordering from the specific position' do
            expect(subject.map(&:id)).to eq([event3.id, event2.id, event1.id])
          end
        end

        context 'when :to_position option is provided' do
          let(:options) { super().merge(to_position: PgEventstore.client.read(stream)[2].global_position) }

          it 'reads events from old to new ordering to the specific position' do
            expect(subject.map(&:id)).to eq([event6.id, event5.id, event4.id, event3.id])
          end
        end
      end

      context 'when no direction is given' do
        it_behaves_like 'historical events order'
      end

      context 'when direction is "Forwards"' do
        let(:options) { { direction: 'Forwards' } }

        it_behaves_like 'historical events order'
      end

      context 'when direction is "asc"' do
        let(:options) { { direction: 'asc' } }

        it_behaves_like 'historical events order'
      end

      context 'when direction is :asc' do
        let(:options) { { direction: :asc } }

        it_behaves_like 'historical events order'
      end

      context 'when direction is "Backwards"' do
        let(:options) { { direction: 'Backwards' } }

        it_behaves_like 'reversed events order'
      end

      context 'when direction is "desc"' do
        let(:options) { { direction: 'desc' } }

        it_behaves_like 'reversed events order'
      end

      context 'when direction is :desc' do
        let(:options) { { direction: :desc } }

        it_behaves_like 'reversed events order'
      end
    end
  end

  describe 'general read cases' do
    let(:stream1) do
      PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
    end
    let(:stream2) do
      PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2')
    end
    let(:stream3) do
      PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1')
    end

    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar') }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Baz') }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar') }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
    let(:event6) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }

    before do
      PgEventstore.client.append_to_stream(stream1, [event1, event2])
      PgEventstore.client.append_to_stream(stream2, [event3, event4, event5])
      PgEventstore.client.append_to_stream(stream3, event6)
    end

    context 'when reading a mix of existing and non-existing stream filters' do
      subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options:) }

      let(:options) { { filter: { streams: [{ context: 'FooCtx', stream_name: 'NonExisting' }, stream3.to_hash] } } }

      it 'returns events for the existing part' do
        expect(subject.map(&:id)).to eq([event6.id])
      end
    end

    context 'when reading a mix of existing and non-existing event type filters' do
      subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options:) }

      let(:options) { { filter: { event_types: %w[NonExisting Baz] } } }

      it 'returns events for the existing part' do
        expect(subject.map(&:id)).to eq([event3.id])
      end
    end

    context 'when reading a mix of existing and non-existing event type and stream filters' do
      subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options:) }

      let(:options) do
        {
          filter: {
            streams: [{ context: 'FooCtx', stream_name: 'NonExisting1' }, stream2.to_hash],
            event_types: %w[NonExisting2 Foo],
          },
        }
      end

      it 'returns events for the existing part' do
        expect(subject.map(&:id)).to eq([event5.id])
      end
    end

    context 'when reading a mix of non-existing stream filters' do
      subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options:) }

      let(:options) do
        { filter: { streams: [{ context: 'FooCtx', stream_name: 'NonExisting1' }, { context: 'NonExisting2' }] } }
      end

      it { is_expected.to eq([]) }
    end

    context 'when combining :from_position, :to_revision, :max_count and :direction' do
      subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options:) }

      describe 'ascending order' do
        let(:options) { { from_position:, to_position:, max_count: 2 } }
        let(:from_position) { safe_read(stream2).first.global_position }
        let(:to_position) { safe_read(stream3).first.global_position }

        it 'returns events according to those restrictions' do
          expect(subject.map(&:id)).to eq([event3.id, event4.id])
        end
      end

      describe 'descending order' do
        let(:options) { { from_position:, to_position:, max_count: 2, direction: :desc } }
        let(:from_position) { safe_read(stream3).first.global_position }
        let(:to_position) { safe_read(stream2).first.global_position }

        it 'returns events according to those restrictions' do
          expect(subject.map(&:id)).to eq([event6.id, event5.id])
        end
      end
    end

    context 'when combining :from_revision, :to_revision, :max_count and :direction' do
      subject { instance.call(stream2, deserializer:, options:) }

      describe 'ascending order' do
        let(:options) { { from_revision: 0, to_revision: 2, max_count: 2 } }

        it 'returns events according to those restrictions' do
          expect(subject.map(&:id)).to eq([event3.id, event4.id])
        end
      end

      describe 'descending order' do
        let(:options) { { from_revision: 2, to_revision: 0, max_count: 2, direction: :desc } }

        it 'returns events according to those restrictions' do
          expect(subject.map(&:id)).to eq([event5.id, event4.id])
        end
      end
    end

    describe 'reading with :max_count == nil' do
      subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options: { max_count: nil }) }

      before do
        stub_const('PgEventstore::QueryBuilders::EventsGlobalIndexFiltering::DEFAULT_LIMIT', 3)
      end

      it 'returns up to DEFAULT_LIMIT events' do
        expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
      end
    end
  end

  describe 'filtering specific stream by markers' do
    subject { instance.call(stream, deserializer:, options:).map { _1.data['id'] } }

    let(:options) { {} }

    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:events) { [] }

    before do
      another_stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2')
      # Create another stream to ensure its events don't appear in the result suddenly
      PgEventstore.client.append_to_stream(another_stream, PgEventstore::Event.new(markers: %w[foo bar baz]))
      PgEventstore.client.append_to_stream(stream, events)
    end

    describe 'matching events by any of the filter markers' do
      let(:options) { { filter: { event_types: [{ markers: %w[foo baz] }] } } }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[bar]) }
      let(:event2) { PgEventstore::Event.new(type: 'Foo', data: { id: 2 }, markers: %w[foo baz]) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[baz]) }
      let(:events) { [event1, event2, event3] }

      it 'returns matching events' do
        is_expected.to eq([2, 3])
      end

      context 'when markers are split into multiple filters' do
        let(:options) { { filter: { event_types: [{ markers: ['foo'] }, { markers: ['baz'] }] } } }

        it 'correctly recognizes them' do
          is_expected.to eq([2, 3])
        end
      end

      describe 'from revision' do
        before do
          options[:from_revision] = 2
        end

        it 'returns matching events from the given revision' do
          is_expected.to eq([3])
        end
      end

      describe 'to revision' do
        before do
          options[:to_revision] = 1
        end

        it 'returns matching events to the given revision' do
          is_expected.to eq([2])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([3, 2])
        end

        describe 'from revision' do
          before do
            options[:from_revision] = 1
          end

          it 'returns matching events from the given revision in descending order' do
            is_expected.to eq([2])
          end
        end
      end
    end

    describe 'matching events by mix of type and marker' do
      let(:options) { { filter: { event_types: [{ markers: %w[foo] }, { type: 'Foo', markers: ['bar'] }] } } }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[bar]) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[foo baz]) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[baz]) }
      let(:events) { [event1, event2, event3] }

      it 'returns matching events' do
        is_expected.to eq([1, 2])
      end

      describe 'from revision' do
        before do
          options[:from_revision] = 1
        end

        it 'returns matching events from the given revision' do
          is_expected.to eq([2])
        end
      end

      describe 'to revision' do
        before do
          options[:to_revision] = 0
        end

        it 'returns matching events to the given revision' do
          is_expected.to eq([1])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([2, 1])
        end

        describe 'from revision' do
          before do
            options[:from_revision] = 0
          end

          it 'returns matching events from the given revision in descending order' do
            is_expected.to eq([1])
          end
        end
      end
    end

    describe 'matching events by type only filter and marker filter' do
      let(:options) { { filter: { event_types: [{ markers: %w[foo] }, 'Foo'] } } }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[bar]) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[foo baz]) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[baz]) }
      let(:event4) { PgEventstore::Event.new(type: 'Baz', data: { id: 4 }) }
      let(:events) { [event1, event2, event3, event4] }

      it 'returns matching events' do
        is_expected.to eq([1, 2, 3])
      end

      describe 'from revision' do
        before do
          options[:from_revision] = 1
        end

        it 'returns matching events from the given revision' do
          is_expected.to eq([2, 3])
        end
      end

      describe 'to revision' do
        before do
          options[:to_revision] = 1
        end

        it 'returns matching events to the given revision' do
          is_expected.to eq([1, 2])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([3, 2, 1])
        end

        describe 'from revision' do
          before do
            options[:from_revision] = 1
          end

          it 'returns matching events from the given revision in descending order' do
            is_expected.to eq([2, 1])
          end
        end
      end
    end

    describe 'matching events by marker filters with type' do
      let(:options) do
        { filter: { event_types: [{ type: 'Foo', markers: %w[foo] }, { type: 'Bar', markers: %w[bar] }] } }
      end

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[foo]) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }) }
      let(:events) { [event1, event2, event3, event4] }

      it 'returns matching events' do
        is_expected.to eq([2, 3])
      end

      describe 'from revision' do
        before do
          options[:from_revision] = 2
        end

        it 'returns matching events from the given revision' do
          is_expected.to eq([3])
        end
      end

      describe 'to revision' do
        before do
          options[:to_revision] = 1
        end

        it 'returns matching events to the given revision' do
          is_expected.to eq([2])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([3, 2])
        end

        describe 'from revision' do
          before do
            options[:from_revision] = 1
          end

          it 'returns matching events from the given revision in descending order' do
            is_expected.to eq([2])
          end
        end
      end
    end

    describe ':to_position, :from_position, :max_count and :direction options in one query' do
      let(:options) do
        {
          filter: {
            event_types: [
              { markers: %w[foo] },
              { type: 'Bar', markers: %w[bar] },
            ],
          },
          from_position: 5,
          to_position: 1,
          direction: :desc,
          max_count: 3,
        }
      end

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[foo]) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[foo bar]) }
      let(:event5) { PgEventstore::Event.new(type: 'Bar', data: { id: 5 }, markers: %w[baz]) }
      let(:event6) { PgEventstore::Event.new(type: 'Bar', data: { id: 6 }, markers: %w[bar]) }
      let(:event7) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }) }
      let(:events) { [event1, event2, event3, event4, event5, event6, event7] }

      it 'returns matching events in the given order, within the given revision range' do
        is_expected.to eq([6, 4, 3])
      end
    end

    describe 'matching events do not exist' do
      let(:options) { { filter: { event_types: [{ markers: %w[foo] }] } } }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[bar]) }
      let(:event2) { PgEventstore::Event.new(type: 'Foo', data: { id: 2 }, markers: %w[baz]) }
      let(:events) { [event1, event2] }

      it { is_expected.to eq([]) }
    end
  end

  describe 'filtering all stream by markers' do
    subject { instance.call(PgEventstore::Stream.all_stream, deserializer:, options:).map { _1.data['id'] } }

    let(:options) { {} }
    let(:events) { [] }

    let(:event_position) do
      lambda do |id|
        PgEventstore.client.read(PgEventstore::Stream.all_stream).find { _1.data['id'] == id }.global_position
      end
    end

    before do
      events.each do |stream, event|
        PgEventstore.client.append_to_stream(stream, event)
      end
    end

    describe 'matching events by any of the filter markers' do
      let(:options) { { filter: { event_types: [{ markers: %w[foo baz] }] } } }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[foo]) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[baz]) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
      let(:event5) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[foo]) }
      let(:event6) { PgEventstore::Event.new(type: 'Bar', data: { id: 6 }, markers: %w[baz]) }
      let(:events) do
        [
          [stream1, event1],
          [stream2, event2],
          [stream1, event3],
          [stream2, event4],
          [stream1, event5],
          [stream2, event6],
        ]
      end

      it 'returns matching events from all streams' do
        is_expected.to eq([2, 3, 5, 6])
      end

      context 'when markers are split into multiple filters' do
        let(:options) { { filter: { event_types: [{ markers: ['foo'] }, { markers: ['baz'] }] } } }

        it 'correctly recognizes them' do
          is_expected.to eq([2, 3, 5, 6])
        end
      end

      describe 'from position' do
        before do
          options[:from_position] = event_position.call(5)
        end

        it 'returns matching events from the given global position' do
          is_expected.to eq([5, 6])
        end
      end

      describe 'to position' do
        before do
          options[:to_position] = event_position.call(3)
        end

        it 'returns matching events to the given global position' do
          is_expected.to eq([2, 3])
        end
      end

      describe 'from position and to position' do
        before do
          options[:from_position] = event_position.call(3)
          options[:to_position] = event_position.call(5)
        end

        it 'returns matching events within the given global position range' do
          is_expected.to eq([3, 5])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([6, 5, 3, 2])
        end

        describe 'from position' do
          before do
            options[:from_position] = event_position.call(5)
          end

          it 'returns matching events from the given global position in descending order' do
            is_expected.to eq([5, 3, 2])
          end
        end

        describe 'to position' do
          before do
            options[:to_position] = event_position.call(5)
          end

          it 'returns matching events to the given global position in descending order' do
            is_expected.to eq([6, 5])
          end
        end
      end
    end

    describe 'matching events by mix of type and marker' do
      let(:options) { { filter: { event_types: [{ markers: %w[bar] }, { type: 'Foo', markers: ['baz'] }] } } }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[baz]) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[foo]) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[bar]) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
      let(:event5) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[baz]) }
      let(:event6) { PgEventstore::Event.new(type: 'Foo', data: { id: 6 }, markers: %w[foo]) }
      let(:events) do
        [
          [stream1, event1],
          [stream2, event2],
          [stream1, event3],
          [stream2, event4],
          [stream1, event5],
          [stream2, event6],
        ]
      end

      it 'returns matching events' do
        is_expected.to eq([1, 3, 4, 5])
      end

      describe 'from position' do
        before do
          options[:from_position] = event_position.call(3)
        end

        it 'returns matching events from the given global position' do
          is_expected.to eq([3, 4, 5])
        end
      end

      describe 'to position' do
        before do
          options[:to_position] = event_position.call(4)
        end

        it 'returns matching events to the given global position' do
          is_expected.to eq([1, 3, 4])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([5, 4, 3, 1])
        end

        describe 'from position' do
          before do
            options[:from_position] = event_position.call(4)
          end

          it 'returns matching events from the given global position in descending order' do
            is_expected.to eq([4, 3, 1])
          end
        end

        describe 'to position' do
          before do
            options[:to_position] = event_position.call(4)
          end

          it 'returns matching events to the given global position in descending order' do
            is_expected.to eq([5, 4])
          end
        end
      end
    end

    describe 'matching events by context and markers' do
      let(:options) { { filter: { streams: [{ context: 'FooCtx' }], event_types: [{ markers: %w[foo] }] } } }

      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::NotSupportedError)
      end
    end

    describe 'matching events by context, stream name and markers' do
      let(:options) do
        {
          filter: {
            streams: [{ context: 'FooCtx', stream_name: 'Foo' }],
            event_types: [{ markers: %w[foo] }],
          },
        }
      end

      it 'raises error' do
        expect { subject }.to raise_error(PgEventstore::NotSupportedError)
      end
    end

    describe 'matching events by context and markers with event types' do
      let(:options) do
        { filter: { streams: [{ context: 'FooCtx' }], event_types: [{ type: 'Bar', markers: %w[bar foo] }] } }
      end

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
      let(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

      let(:event1) { PgEventstore::Event.new(type: 'Bar', data: { id: 1 }, markers: %w[foo]) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
      let(:event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 3 }, markers: %w[foo bar]) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
      let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[bar]) }
      let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[bar]) }
      let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[baz]) }
      let(:unmatched_event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 8 }, markers: %w[bar]) }

      let(:events) do
        [
          [stream1, unmatched_event1],
          [stream1, event1],
          [stream2, unmatched_event2],
          [stream2, event2],
          [stream1, unmatched_event3],
          [stream1, event3],
          [stream2, event4],
          [stream3, unmatched_event4],
        ]
      end

      it 'returns matching events' do
        is_expected.to eq([1, 2, 3, 4])
      end

      describe 'from position' do
        before do
          options[:from_position] = event_position.call(2)
        end

        it 'returns matching events from the given global position' do
          is_expected.to eq([2, 3, 4])
        end
      end

      describe 'to position' do
        before do
          options[:to_position] = event_position.call(2)
        end

        it 'returns matching events to the given global position' do
          is_expected.to eq([1, 2])
        end
      end

      describe 'from position and to position' do
        before do
          options[:from_position] = event_position.call(2)
          options[:to_position] = event_position.call(4)
        end

        it 'returns matching events within the given global position range' do
          is_expected.to eq([2, 3, 4])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([4, 3, 2, 1])
        end

        describe 'from position' do
          before do
            options[:from_position] = event_position.call(3)
          end

          it 'returns matching events from the given global position in descending order' do
            is_expected.to eq([3, 2, 1])
          end
        end

        describe 'to position' do
          before do
            options[:to_position] = event_position.call(3)
          end

          it 'returns matching events to the given global position in descending order' do
            is_expected.to eq([4, 3])
          end
        end
      end
    end

    describe 'matching events by context, stream name and markers with event types' do
      let(:options) do
        {
          filter: {
            streams: [{ context: 'FooCtx', stream_name: 'Foo' }],
            event_types: [{ type: 'Bar', markers: %w[bar foo] }],
          },
        }
      end

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
      let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

      let(:event1) { PgEventstore::Event.new(type: 'Bar', data: { id: 1 }, markers: %w[foo]) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
      let(:event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 3 }, markers: %w[foo bar]) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
      let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[bar]) }
      let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[bar]) }
      let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[baz]) }
      let(:unmatched_event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 8 }, markers: %w[bar]) }

      let(:events) do
        [
          [stream1, unmatched_event1],
          [stream1, event1],
          [stream2, unmatched_event2],
          [stream2, event2],
          [stream1, unmatched_event3],
          [stream1, event3],
          [stream2, event4],
          [stream3, unmatched_event4],
        ]
      end

      it 'returns matching events' do
        is_expected.to eq([1, 2, 3, 4])
      end

      describe 'from position' do
        before do
          options[:from_position] = event_position.call(2)
        end

        it 'returns matching events from the given global position' do
          is_expected.to eq([2, 3, 4])
        end
      end

      describe 'to position' do
        before do
          options[:to_position] = event_position.call(2)
        end

        it 'returns matching events to the given global position' do
          is_expected.to eq([1, 2])
        end
      end

      describe 'from position and to position' do
        before do
          options[:from_position] = event_position.call(2)
          options[:to_position] = event_position.call(4)
        end

        it 'returns matching events within the given global position range' do
          is_expected.to eq([2, 3, 4])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([4, 3, 2, 1])
        end

        describe 'from position' do
          before do
            options[:from_position] = event_position.call(3)
          end

          it 'returns matching events from the given global position in descending order' do
            is_expected.to eq([3, 2, 1])
          end
        end

        describe 'to position' do
          before do
            options[:to_position] = event_position.call(3)
          end

          it 'returns matching events to the given global position in descending order' do
            is_expected.to eq([4, 3])
          end
        end
      end
    end

    describe 'matching events by stream and markers' do
      let(:options) { { filter: { streams: [stream1.to_hash], event_types: [{ markers: %w[bar foo] }] } } }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[foo]) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
      let(:event3) { PgEventstore::Event.new(type: 'Baz', data: { id: 3 }, markers: %w[foo bar]) }
      let(:event4) { PgEventstore::Event.new(type: 'FooBar', data: { id: 4 }, markers: %w[bar]) }
      let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[baz]) }
      let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[foo-baz]) }
      let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[foo]) }

      let(:events) do
        [
          [stream1, unmatched_event1],
          [stream1, event1],
          [stream1, unmatched_event2],
          [stream1, event2],
          [stream2, unmatched_event3],
          [stream1, event3],
          [stream1, event4],
        ]
      end

      it 'returns matching events' do
        is_expected.to eq([1, 2, 3, 4])
      end

      describe 'from position' do
        before do
          options[:from_position] = event_position.call(2)
        end

        it 'returns matching events from the given global position' do
          is_expected.to eq([2, 3, 4])
        end
      end

      describe 'to position' do
        before do
          options[:to_position] = event_position.call(2)
        end

        it 'returns matching events to the given global position' do
          is_expected.to eq([1, 2])
        end
      end

      describe 'from position and to position' do
        before do
          options[:from_position] = event_position.call(2)
          options[:to_position] = event_position.call(4)
        end

        it 'returns matching events within the given global position range' do
          is_expected.to eq([2, 3, 4])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([4, 3, 2, 1])
        end

        describe 'from position' do
          before do
            options[:from_position] = event_position.call(3)
          end

          it 'returns matching events from the given global position in descending order' do
            is_expected.to eq([3, 2, 1])
          end
        end

        describe 'to position' do
          before do
            options[:to_position] = event_position.call(3)
          end

          it 'returns matching events to the given global position in descending order' do
            is_expected.to eq([4, 3])
          end
        end

        describe 'from position and to position' do
          before do
            options[:from_position] = event_position.call(4)
            options[:to_position] = event_position.call(2)
          end

          it 'returns matching events within the given global position range' do
            is_expected.to eq([4, 3, 2])
          end
        end
      end
    end

    describe 'matching events by stream and markers with event types' do
      let(:options) { { filter: { streams: [stream1.to_hash], event_types: [{ type: 'Bar', markers: %w[bar foo] }] } } }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

      let(:event1) { PgEventstore::Event.new(type: 'Bar', data: { id: 1 }, markers: %w[foo]) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[bar]) }
      let(:event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 3 }, markers: %w[foo bar]) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[bar]) }
      let(:unmatched_event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[foo bar]) }
      let(:unmatched_event2) { PgEventstore::Event.new(type: 'FooBar', data: { id: 6 }, markers: %w[bar]) }
      let(:unmatched_event3) { PgEventstore::Event.new(type: 'Bar', data: { id: 7 }, markers: %w[bar]) }

      let(:events) do
        [
          [stream1, unmatched_event1],
          [stream1, event1],
          [stream1, unmatched_event2],
          [stream1, event2],
          [stream2, unmatched_event3],
          [stream1, event3],
          [stream1, event4],
        ]
      end

      it 'returns matching events' do
        is_expected.to eq([1, 2, 3, 4])
      end

      describe 'from position' do
        before do
          options[:from_position] = event_position.call(2)
        end

        it 'returns matching events from the given global position' do
          is_expected.to eq([2, 3, 4])
        end
      end

      describe 'to position' do
        before do
          options[:to_position] = event_position.call(2)
        end

        it 'returns matching events to the given global position' do
          is_expected.to eq([1, 2])
        end
      end

      describe 'from position and to position' do
        before do
          options[:from_position] = event_position.call(2)
          options[:to_position] = event_position.call(4)
        end

        it 'returns matching events within the given global position range' do
          is_expected.to eq([2, 3, 4])
        end
      end

      describe 'descending sorting order' do
        before do
          options[:direction] = :desc
        end

        it 'returns matching events in reverse order' do
          is_expected.to eq([4, 3, 2, 1])
        end

        describe 'from position' do
          before do
            options[:from_position] = event_position.call(3)
          end

          it 'returns matching events from the given global position in descending order' do
            is_expected.to eq([3, 2, 1])
          end
        end

        describe 'to position' do
          before do
            options[:to_position] = event_position.call(3)
          end

          it 'returns matching events to the given global position in descending order' do
            is_expected.to eq([4, 3])
          end
        end

        describe 'from position and to position' do
          before do
            options[:from_position] = event_position.call(4)
            options[:to_position] = event_position.call(2)
          end

          it 'returns matching events within the given global position range' do
            is_expected.to eq([4, 3, 2])
          end
        end
      end
    end

    describe ':to_position, :from_position, :max_count and :direction options in one query' do
      let(:options) do
        {
          filter: {
            event_types: [
              { markers: %w[foo] },
              { type: 'Bar', markers: %w[bar] },
            ],
          },
          from_position: event_position.call(6),
          to_position: event_position.call(2),
          direction: :desc,
          max_count: 3,
        }
      end

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }) }
      let(:event2) { PgEventstore::Event.new(type: 'Bar', data: { id: 2 }, markers: %w[foo]) }
      let(:event3) { PgEventstore::Event.new(type: 'Foo', data: { id: 3 }, markers: %w[foo]) }
      let(:event4) { PgEventstore::Event.new(type: 'Bar', data: { id: 4 }, markers: %w[foo bar]) }
      let(:event5) { PgEventstore::Event.new(type: 'Foo', data: { id: 5 }, markers: %w[baz]) }
      let(:event6) { PgEventstore::Event.new(type: 'Bar', data: { id: 6 }, markers: %w[bar]) }
      let(:event7) { PgEventstore::Event.new(type: 'Foo', data: { id: 7 }, markers: %w[baz]) }
      let(:events) do
        [
          [stream1, event1],
          [stream2, event2],
          [stream1, event3],
          [stream2, event4],
          [stream1, event5],
          [stream2, event6],
          [stream1, event7],
        ]
      end

      it 'returns matching events in the given order, within the given global position range' do
        is_expected.to eq([6, 4, 3])
      end
    end

    describe 'matching events do not exist' do
      let(:options) { { filter: { event_types: [{ markers: %w[foo] }] } } }

      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

      let(:event1) { PgEventstore::Event.new(type: 'Foo', data: { id: 1 }, markers: %w[bar]) }
      let(:event2) { PgEventstore::Event.new(type: 'Foo', data: { id: 2 }, markers: %w[baz]) }
      let(:events) { [[stream, event1], [stream, event2]] }

      it { is_expected.to eq([]) }
    end
  end
end

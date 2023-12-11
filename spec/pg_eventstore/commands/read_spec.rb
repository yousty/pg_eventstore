# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::Read do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(
      PgEventstore.connection, PgEventstore::EventSerializer.new(middlewares),
      PgEventstore::PgResultDeserializer.new(middlewares, event_class_resolver)
    )
  end
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }

  describe '#call' do
    subject { instance.call(stream, options: options) }

    let(:options) { {} }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream2', stream_id: '1234')
    end
    let(:stream) { events_stream1 }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :baz) }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :baz) }

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
      let!(:link) do
        # TODO: use LinkTo command here when it will be implemented instead manual query
        queries.insert(
          existing_event.stream,
          PgEventstore::Event.new(link_id: existing_event.id, stream_revision: 1, type: PgEventstore::Event::LINK_TYPE)
        )
      end
      let(:stream) { events_stream2 }

      context 'when :resolve_link_tos is not provided' do
        it 'returns links as is' do
          expect(subject.map(&:id)).to eq([existing_event.id, link.id])
        end
      end

      context 'when :resolve_link_tos is provided' do
        let(:options) { { resolve_link_tos: true } }

        it 'resolves links to original events' do
          expect(subject.map(&:id)).to eq([existing_event.id, existing_event.id])
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

    context 'when middleware is present' do
      let(:middlewares) { [DummyMiddleware.new] }

      it 'modifies the event using it' do
        expect(subject.first.metadata).to eq('dummy_secret' => DummyMiddleware::DECR_SECRET)
      end
    end
  end

  describe 'event class resolving' do
    subject { instance.call(stream, options: {}) }

    let(:event_class) { Class.new(PgEventstore::Event) }
    let(:event) { event_class.new }
    let(:stream) { PgEventstore::Stream.new(context: 'ctx', stream_name: 'foo', stream_id: 'bar') }

    before do
      stub_const('DummyClass', event_class)
      PgEventstore.client.append_to_stream(stream, event)
    end

    it "recognizes event's class" do
      expect(subject.first).to be_a(DummyClass)
    end
  end

  describe 'reading using filter by stream parts' do
    subject { instance.call(stream, options: options) }

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
    let(:stream) { events_stream1 }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :baz) }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }

    before do
      PgEventstore.client.append_to_stream(events_stream1, event1)
      PgEventstore.client.append_to_stream(events_stream2, event2)
      PgEventstore.client.append_to_stream(events_stream3, event3)
      PgEventstore.client.append_to_stream(events_stream4, event4)
      PgEventstore.client.append_to_stream(events_stream5, event5)
    end

    describe 'filtering by the context' do
      let(:options) { { filter: { streams: [{ context: 'SomeContext' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given context' do
          expect(subject.map(&:id)).to eq([event1.id, event3.id])
        end
      end
    end

    describe 'filtering by the stream name only' do
      let(:options) { { filter: { streams: [{ stream_name: 'some-stream1' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id, event4.id, event5.id])
        end
      end
    end

    describe 'filtering by two different contexts' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext' }, { context: 'SomeAnotherContext2' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given contexts' do
          expect(subject.map(&:id)).to eq([event2.id, event4.id, event5.id])
        end
      end
    end

    describe 'filtering by stream name and context as a part of the same stream' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext', stream_name: 'some-stream1' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given stream name and context' do
          expect(subject.map(&:id)).to eq([event2.id, event5.id])
        end
      end
    end

    describe 'filtering by several stream names and contexts' do
      let(:options) do
        {
          filter: {
            streams: [
              { context: 'SomeAnotherContext', stream_name: 'some-stream1' },
              { context: 'SomeContext', stream_name: 'some-stream1' }
            ]
          }
        }
      end

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given stream names and contexts' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event5.id])
        end
      end
    end

    describe 'filtering by stream name and context as a part of different streams' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext' }, { stream_name: 'some-stream1' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events that match context only, ignoring stream_name' do
          expect(subject.map(&:id)).to eq([event2.id, event5.id])
        end
      end
    end

    describe 'filtering by several specific streams' do
      let(:options) { { filter: { streams: [events_stream1.to_hash, events_stream4.to_hash] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events of those streams' do
          expect(subject.map(&:id)).to eq([event1.id, event4.id])
        end
      end
    end

    describe 'filtering by the stream id only' do
      let(:options) { { filter: { streams: [{ stream_id: '1234' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id, event4.id, event5.id])
        end
      end
    end

    describe 'filtering by context and stream id as a part of different streams' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext2' }, { stream_id: '123' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events that match the given context only, ignoring stream id' do
          expect(subject.map(&:id)).to eq([event4.id])
        end
      end
    end

    describe 'filtering by stream name and stream id as a part of different streams' do
      let(:options) { { filter: { streams: [{ stream_name: 'some-stream3' }, { stream_id: '1234' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id, event4.id, event5.id])
        end
      end
    end
  end

  describe 'reading using filter by event type' do
    subject { instance.call(stream, options: options) }

    let(:options) { { filter: { event_types: %w[foo baz] } } }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream2', stream_id: '123')
    end
    let(:stream) { events_stream1 }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :baz) }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }

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
    subject { instance.call(stream, options: options) }

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
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :baz) }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }

    before do
      PgEventstore.client.append_to_stream(events_stream1, [event1, event2])
      PgEventstore.client.append_to_stream(events_stream2, [event3, event4])
      PgEventstore.client.append_to_stream(events_stream3, [event5])
    end

    context 'when reading from regular stream' do
      it 'filters events only by the given types' do
        expect(subject.map(&:id)).to eq([event1.id])
      end
    end

    context 'when reading from "all" stream' do
      let(:stream) { PgEventstore::Stream.all_stream }

      it 'filters events by the given event types and by the given stream parts' do
        expect(subject.map(&:id)).to eq([event1.id, event5.id])
      end
    end
  end

  describe 'direction of reading from a position/revision' do
    subject { instance.call(stream, options: options) }

    let(:options) { {} }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream2', stream_id: '123')
    end
    let(:stream) { events_stream2 }
    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :baz) }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :bar) }
    let(:event5) { PgEventstore::Event.new(id: SecureRandom.uuid, type: :foo) }

    before do
      PgEventstore.client.append_to_stream(events_stream1, [event1, event2])
      PgEventstore.client.append_to_stream(events_stream2, [event3, event4, event5])
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
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id, event4.id, event5.id])
        end

        context 'when :from_position option is provided' do
          let(:options) { super().merge(from_position: PgEventstore.client.read(stream)[2].global_position) }

          it 'reads events in historical order from the specific position' do
            expect(subject.map(&:id)).to eq([event3.id, event4.id, event5.id])
          end
        end
      end

      shared_examples 'reversed events order' do
        it 'reads events from old to new ordering' do
          expect(subject.map(&:id)).to eq([event5.id, event4.id, event3.id, event2.id, event1.id])
        end

        context 'when :from_position option is provided' do
          let(:options) { super().merge(from_position: PgEventstore.client.read(stream)[2].global_position) }

          it 'reads events from old to new ordering from the specific position' do
            expect(subject.map(&:id)).to eq([event3.id, event2.id, event1.id])
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
end

# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::Read do
  let(:instance) { described_class.new(PgEventstore.connection, middlewares, event_class_resolver) }
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

    context 'when :direction option is given' do
      context 'when value of it is "Backwards"' do
        let(:options) { { direction: 'Backwards' } }

        it 'returns events in descending order' do
          expect(subject.map(&:id)).to eq([event3.id, event2.id, event1.id])
        end
      end

      context 'when value of it is "Forwards"' do
        let(:options) { { direction: 'Forwards' } }

        it 'returns events in ascending order' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
        end
      end

      context 'when value of it is something else' do
        let(:options) { { direction: 'some unhandled direction value' } }

        it 'returns events in ascending order' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
        end
      end
    end

    context 'when :from_revision option is given' do
      let(:options) { { from_revision: 1 } }

      context 'when reading from regular stream' do
        it 'returns events, starting from the given stream revision' do
          expect(subject.map(&:id)).to eq([event2.id, event3.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id, event4.id])
        end
      end
    end

    context 'when :from_position option is given' do
      let(:options) { { from_position: PgEventstore.client.read(events_stream1).last(2).first.global_position } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event3.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns events, starting from the given global position' do
          expect(subject.map(&:id)).to eq([event2.id, event3.id, event4.id])
        end
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
        instance.send(:queries).insert(
          PgEventstore::Event.new(link_id: existing_event.global_position, stream_revision: 1, **existing_event.stream)
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

    describe 'filtering by the stream name' do
      let(:options) { { filter: { streams: [{ stream_name: 'some-stream1' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given stream name' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event5.id])
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

    describe 'filtering by two different stream names' do
      let(:options) { { filter: { streams: [{ stream_name: 'some-stream1' }, { stream_name: 'some-stream3' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events within the given stream names' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event4.id, event5.id])
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

    describe 'filtering by stream name and context as a part of different streams' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext' }, { stream_name: 'some-stream1' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events that match either stream name or context' do
          expect(subject.map(&:id)).to eq([event1.id, event2.id, event5.id])
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

    describe 'filtering by the stream id' do
      let(:options) { { filter: { streams: [{ stream_id: '1234' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events by the given stream id' do
          expect(subject.map(&:id)).to eq([event3.id, event4.id])
        end
      end
    end

    describe 'filtering by several different stream ids' do
      let(:options) { { filter: { streams: [{ stream_id: '1234' }, { stream_id: '123' }] } } }

      context 'when reading from regular stream' do
        it 'ignores it' do
          expect(subject.map(&:id)).to eq([event1.id])
        end
      end

      context 'when reading from "all" stream' do
        let(:stream) { PgEventstore::Stream.all_stream }

        it 'returns all events by the given stream ids' do
          expect(subject.map(&:id)).to eq([event1.id, event3.id, event4.id])
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

        it 'returns all events that match either the given context or the given stream id' do
          expect(subject.map(&:id)).to eq([event1.id, event4.id])
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

        it 'returns all events that match either the given stream name or the given stream id' do
          expect(subject.map(&:id)).to eq([event3.id, event4.id])
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

    let(:options) { { filter: { event_types: %w[foo baz], streams: [{ stream_name: 'some-stream2' }] } } }
    let(:events_stream1) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream1', stream_id: '123')
    end
    let(:events_stream2) do
      PgEventstore::Stream.new(context: 'SomeAnotherContext', stream_name: 'some-stream2', stream_id: '123')
    end
    let(:events_stream3) do
      PgEventstore::Stream.new(context: 'SomeContext', stream_name: 'some-stream2', stream_id: '123')
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
        expect(subject.map(&:id)).to eq([event3.id, event5.id])
      end
    end
  end
end

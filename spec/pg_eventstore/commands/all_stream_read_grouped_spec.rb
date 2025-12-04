# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::AllStreamReadGrouped do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(events: event_queries, partitions: partition_queries)
  end
  let(:partition_queries) { PgEventstore::PartitionQueries.new(PgEventstore.connection) }
  let(:event_queries) do
    PgEventstore::EventQueries.new(
      PgEventstore.connection,
      PgEventstore::EventSerializer.new(middlewares),
      PgEventstore::EventDeserializer.new(middlewares, event_class_resolver)
    )
  end
  let(:middlewares) { [] }
  let(:event_class_resolver) { PgEventstore::EventClassResolver.new }

  describe '#call' do
    subject { instance.call(PgEventstore::Stream.all_stream, options: options) }

    let(:options) { {} }

    let!(:event1) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000001', type: 'Foo') }
    let!(:event2) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000002', type: 'Bar') }
    let!(:event3) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000003', type: 'Baz') }
    let!(:event4) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000004', type: 'Foo') }
    let!(:event5) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000005', type: 'Baz') }

    let!(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let!(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
    let!(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '3') }

    before do
      # Append events in non-sequential order to simulate real events distribution
      PgEventstore.client.append_to_stream(stream1, [event1, event2])
      PgEventstore.client.append_to_stream(stream2, event3)
      PgEventstore.client.append_to_stream(stream3, [event4, event5])
    end

    context 'when same event types appear in same context/stream name streams' do
      context 'when direction is "Forwards"' do
        it 'returns a projection by oldest events' do
          expect(subject.map(&:id)).to match_array([event1.id, event2.id, event3.id])
        end

        context 'when :from_position option is provided' do
          let(:options) { { from_position: from_position } }
          let(:from_position) do
            PgEventstore.client.read(PgEventstore::Stream.all_stream).find do
              _1.id == event2.id
            end.global_position
          end

          it 'returns a projection by oldest events starting from the given position' do
            expect(subject.map(&:id)).to match_array([event2.id, event3.id, event4.id])
          end
        end
      end

      context 'when direction is "Backwards"' do
        let(:options) { { direction: 'Backwards' } }

        it 'returns a projection by newest events' do
          expect(subject.map(&:id)).to match_array([event4.id, event2.id, event5.id])
        end

        context 'when :from_position option is provided' do
          let(:options) { super().merge(from_position: from_position) }
          let(:from_position) do
            PgEventstore.client.read(PgEventstore::Stream.all_stream).find do
              _1.id == event2.id
            end.global_position
          end

          it 'returns a projection by newest events starting from the given position' do
            expect(subject.map(&:id)).to match_array([event2.id, event1.id])
          end
        end
      end
    end

    context 'when same event types appear in streams with different stream name' do
      let!(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '3') }

      it 'considers an event type from different stream names as a different type' do
        expect(subject.map(&:id)).to match_array([event1.id, event2.id, event3.id, event4.id, event5.id])
      end
    end

    context 'when same event types appear in streams with different context' do
      let!(:stream3) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Foo', stream_id: '3') }

      it 'considers an event type from different contexts as a different type' do
        expect(subject.map(&:id)).to match_array([event1.id, event2.id, event3.id, event4.id, event5.id])
      end
    end
  end

  describe 'reading links' do
    subject { instance.call(PgEventstore::Stream.all_stream, options: options) }

    let(:options) { {} }

    let!(:existing_event1) do
      event = PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000001', type: 'Foo')
      PgEventstore.client.append_to_stream(stream, event)
    end
    let!(:existing_event2) do
      event = PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000002', type: 'Bar')
      PgEventstore.client.append_to_stream(stream, event)
    end
    let!(:existing_event3) do
      event = PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000003', type: 'Bar')
      PgEventstore.client.append_to_stream(stream, event)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    let(:projection_stream) do
      PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyProjection', stream_id: '1')
    end
    let!(:link1) do
      PgEventstore.client.link_to(projection_stream, existing_event1)
    end
    let!(:link2) do
      PgEventstore.client.link_to(projection_stream, existing_event2)
    end

    it 'returns a projection by all events, including "link" event type' do
      is_expected.to match_array([existing_event1, existing_event2, link1])
    end

    context 'when :resolve_link_tos is provided' do
      let(:options) { { resolve_link_tos: true } }

      it 'returns original events, projected by "link" event type' do
        is_expected.to match_array([existing_event1, existing_event2, existing_event1])
      end
    end
  end

  it_behaves_like 'resolves event class when reading from stream'

  describe 'reading using filter by stream parts' do
    subject { instance.call(PgEventstore::Stream.all_stream, options: options) }

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

    let(:event1) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000001', type: 'foo') }
    let(:event2) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000002', type: 'bar') }
    let(:event3) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000003', type: 'baz') }
    let(:event4) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000004', type: 'bar') }
    let(:event5) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000005', type: 'foo') }

    let(:event6) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000006', type: 'foo') }
    let(:event7) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000007', type: 'bar') }
    let(:event8) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000008', type: 'baz') }
    let(:event9) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000009', type: 'bar') }
    let(:event10) { PgEventstore::Event.new(id: '00000000-0000-0000-0000-000000000010', type: 'foo') }

    before do
      PgEventstore.client.append_to_stream(events_stream1, [event1, event6])
      PgEventstore.client.append_to_stream(events_stream2, [event2, event7])
      PgEventstore.client.append_to_stream(events_stream3, [event3, event8])
      PgEventstore.client.append_to_stream(events_stream4, [event4, event9])
      PgEventstore.client.append_to_stream(events_stream5, [event5, event10])
    end

    describe 'filtering by the context' do
      let(:options) { { filter: { streams: [{ context: 'SomeContext' }] } } }

      it 'projects all events within the given context' do
        expect(subject.map(&:id)).to match_array([event1.id, event3.id])
      end

      context 'when reading from a certain position' do
        let(:options) { super().merge(from_position: from_position) }
        let(:from_position) do
          PgEventstore.client.read(PgEventstore::Stream.all_stream).find do
            _1.id == event6.id
          end.global_position
        end

        it 'projects all events within the given context in reversed oder, from the given position' do
          expect(subject.map(&:id)).to match_array([event6.id, event3.id])
        end
      end

      context 'when reading backwards' do
        let(:options) { super().merge(direction: 'Backwards') }

        it 'projects all events within the given context in reversed oder' do
          expect(subject.map(&:id)).to match_array([event8.id, event6.id])
        end

        context 'when reading from a certain position' do
          let(:options) { super().merge(from_position: from_position) }
          let(:from_position) do
            PgEventstore.client.read(PgEventstore::Stream.all_stream).find do
              _1.id == event3.id
            end.global_position
          end

          it 'projects all events within the given context in reversed oder, from the given position' do
            expect(subject.map(&:id)).to match_array([event6.id, event3.id])
          end
        end
      end
    end

    describe 'filtering by the stream name only' do
      let(:options) { { filter: { streams: [{ stream_name: 'some-stream1' }] } } }

      it 'ignores it, projection all events' do
        expect(subject.map(&:id)).to match_array([event1.id, event2.id, event3.id, event4.id, event5.id])
      end
    end

    describe 'filtering by two different contexts' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext' }, { context: 'SomeAnotherContext2' }] } } }

      it 'projects all events within the given contexts' do
        expect(subject.map(&:id)).to match_array([event2.id, event4.id, event5.id])
      end
    end

    describe 'filtering by stream name and context as a part of the same filter' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext', stream_name: 'some-stream1' }] } } }

      it 'projects all events within the given stream name and context' do
        expect(subject.map(&:id)).to match_array([event2.id, event5.id])
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

      it 'projects all events within the given stream names and contexts' do
        expect(subject.map(&:id)).to match_array([event1.id, event2.id, event5.id])
      end
    end

    describe 'filtering by stream name and context as a part of different streams' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext' }, { stream_name: 'some-stream1' }] } } }

      it 'projects all events that match context only, ignoring stream_name' do
        expect(subject.map(&:id)).to match_array([event2.id, event5.id])
      end
    end

    describe 'filtering by several specific streams' do
      let(:options) { { filter: { streams: [events_stream1.to_hash, events_stream4.to_hash] } } }

      it 'projects all events of those streams' do
        expect(subject.map(&:id)).to match_array([event1.id, event4.id])
      end
    end

    describe 'filtering by the stream id only' do
      let(:options) { { filter: { streams: [{ stream_id: '1234' }] } } }

      it 'ignores it, projection all events' do
        expect(subject.map(&:id)).to match_array([event1.id, event2.id, event3.id, event4.id, event5.id])
      end
    end

    describe 'filtering by context and stream id as a part of different filters' do
      let(:options) { { filter: { streams: [{ context: 'SomeAnotherContext2' }, { stream_id: '123' }] } } }

      it 'projects all events that match the given context only, ignoring stream id' do
        expect(subject.map(&:id)).to match_array([event4.id])
      end
    end

    describe 'filtering by stream name and stream id as a part of different filters' do
      let(:options) { { filter: { streams: [{ stream_name: 'some-stream3' }, { stream_id: '1234' }] } } }

      it 'ignores it, projection all events' do

        expect(subject.map(&:id)).to match_array([event1.id, event2.id, event3.id, event4.id, event5.id])
      end
    end
  end
end

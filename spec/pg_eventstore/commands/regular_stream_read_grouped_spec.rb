# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::RegularStreamReadGrouped do
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
    context 'when reading from existing stream' do
      subject { instance.call(stream1, options: options) }

      let(:options) { {} }

      let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }
      let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar') }
      let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Baz') }
      let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo') }

      let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }

      before do
        # Append events in non-sequential order to simulate real events distribution
        PgEventstore.client.append_to_stream(stream1, [event1, event2])
        PgEventstore.client.append_to_stream(stream2, event3)
        PgEventstore.client.append_to_stream(stream1, event4)
      end

      context 'when :direction is "Forwards"' do
        it 'returns a projection of the oldest events' do
          expect(subject.map(&:id)).to match_array([event1.id, event2.id])
        end

        context 'when :from_revision option is given' do
          let(:options) { { from_revision: 1 } }

          it 'returns a projection of the oldest events from the given revision' do
            expect(subject.map(&:id)).to match_array([event2.id, event4.id])
          end
        end
      end

      context 'when :direction is "Backwards"' do
        let(:options) { { direction: 'Backwards' } }

        it 'returns a projection of the newest events' do
          expect(subject.map(&:id)).to match_array([event4.id, event2.id])
        end

        context 'when :from_revision option is given' do
          let(:options) { super().merge(from_revision: 1) }

          it 'returns a projection of the newest events from the given revision' do
            expect(subject.map(&:id)).to match_array([event1.id, event2.id])
          end
        end
      end

      context 'when event types filter is provided' do
        let(:options) { { filter: { event_types: ['Foo'] } } }

        it 'returns a projection of the given event types' do
          expect(subject.map(&:id)).to match_array([event1.id])
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

    context 'when reading from non-existing stream' do
      subject { instance.call(stream) }

      let(:stream) { PgEventstore::Stream.new(context: 'SomeCtx', stream_name: 'Foo', stream_id: '1') }

      it 'raises error' do
        expect { subject.to_a }.to raise_error(PgEventstore::StreamNotFoundError)
      end
    end

    describe 'reading links' do
      subject { instance.call(projection_stream, options: options) }

      let(:options) { {} }

      let(:existing_event1) do
        event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Foo')
        PgEventstore.client.append_to_stream(stream, event)
      end
      let(:existing_event2) do
        event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar')
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

      it 'returns a projection by "link" event type' do
        is_expected.to eq([link1])
      end

      context 'when projection stream contains regular event' do
        let!(:existing_event3) do
          event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar')
          PgEventstore.client.append_to_stream(projection_stream, event)
        end

        it 'includes it into a projection' do
          is_expected.to match_array([link1, existing_event3])
        end
      end

      context 'when :resolve_link_tos is provided' do
        let(:options) { { resolve_link_tos: true } }

        it 'returns original events, projected by "link" event type' do
          is_expected.to eq([existing_event1])
        end

        context 'when projection stream contains regular event' do
          let!(:existing_event3) do
            event = PgEventstore::Event.new(id: SecureRandom.uuid, type: 'Bar')
            PgEventstore.client.append_to_stream(projection_stream, event)
          end

          it 'includes it into a projection' do
            is_expected.to match_array([existing_event1, existing_event3])
          end
        end
      end
    end
  end

  it_behaves_like 'resolves event class when reading from stream'
end

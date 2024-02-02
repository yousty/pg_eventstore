# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::SystemStreamReadPaginated do
  let(:instance) { described_class.new(queries) }
  let(:queries) do
    PgEventstore::Queries.new(events: event_queries, streams: stream_queries)
  end
  let(:stream_queries) { PgEventstore::StreamQueries.new(PgEventstore.connection) }
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
    
    let(:options) { { max_count: 2, filter: { streams: [{ context: 'FooCtx' }] } } }

    let(:event1) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:event2) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:event3) { PgEventstore::Event.new(id: SecureRandom.uuid) }
    let(:event4) { PgEventstore::Event.new(id: SecureRandom.uuid) }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Foo', stream_id: '2') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }

    before do
      # Append events in non-sequential order to simulate real events distribution
      PgEventstore.client.append_to_stream(stream1, [event1, event2])
      PgEventstore.client.append_to_stream(stream2, event3)
      PgEventstore.client.append_to_stream(stream3, event4)
    end

    shared_examples 'fast execution' do
      context 'when not filtering by event type' do
        before do
          PgEventstore.client.append_to_stream(stream2, Array.new(1_000) { PgEventstore::Event.new })
        end

        it 'does not take much time to complete reading all events' do
          time = Benchmark.realtime { subject.to_a } * 1000
          expect(time).to be < 6# milliseconds
        end
      end

      context 'when using event types filter' do
        let(:options) do
          super().tap do |opts|
            opts[:filter][:event_types] = ['PgEventstore::Event']
          end
        end

        before do
          PgEventstore.client.append_to_stream(stream1, Array.new(1_000) { PgEventstore::Event.new(type: 'Foo') })
        end

        it 'does not take much time to complete reading all events' do
          time = Benchmark.realtime { subject.to_a } * 1000
          expect(time).to be < 6 # milliseconds
        end
      end
    end

    it { is_expected.to be_a(Enumerator) }

    context 'when :direction is "Forwards"' do
      it 'returns events in the correct order' do
        aggregate_failures do
          expect(subject.next.map(&:id)).to eq([event1.id, event2.id])
          expect(subject.next.map(&:id)).to eq([event4.id])
          expect { subject.next }.to raise_error(StopIteration)
        end
      end
      it_behaves_like 'fast execution'

      context 'when :from_position option is given' do
        let(:options) { super().merge(from_position: PgEventstore.client.read(stream1).last.global_position) }

        it 'returns events starting from the given revision' do
          aggregate_failures do
            expect(subject.next.map(&:id)).to eq([event2.id, event4.id])
            expect { subject.next }.to raise_error(StopIteration)
          end
        end
      end
    end

    context 'when :direction options is "Backwards"' do
      let(:options) { super().merge(direction: 'Backwards') }

      it 'returns events in the correct order' do
        aggregate_failures do
          expect(subject.next.map(&:id)).to eq([event4.id, event2.id])
          expect(subject.next.map(&:id)).to eq([event1.id])
          expect { subject.next }.to raise_error(StopIteration)
        end
      end
      it_behaves_like 'fast execution'

      context 'when :from_position option is given' do
        let(:options) { super().merge(from_position: PgEventstore.client.read(stream1).last.global_position) }

        it 'returns events starting from the given revision' do
          aggregate_failures do
            expect(subject.next.map(&:id)).to eq([event2.id, event1.id])
            expect { subject.next }.to raise_error(StopIteration)
          end
        end
      end
    end
  end
end

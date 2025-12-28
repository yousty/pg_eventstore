# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::SystemStreamReadPaginated do
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
      context 'when not filtering by event type', :skip_ci do
        before do
          PgEventstore.client.append_to_stream(stream2, Array.new(1_000) { PgEventstore::Event.new })
        end

        it 'does not take much time to complete reading all events' do
          time = PgEventstore::Utils.benchmark { subject.to_a } * 1000
          # milliseconds. Keep in mind that this assertion includes performance degradation due to RBS testing
          expect(time).to be < 30
        end
      end

      context 'when using event types filter', :skip_ci do
        let(:options) do
          super().tap do |opts|
            opts[:filter][:event_types] = ['PgEventstore::Event']
          end
        end

        before do
          PgEventstore.client.append_to_stream(stream1, Array.new(1_000) { PgEventstore::Event.new(type: 'Foo') })
        end

        it 'does not take much time to complete reading all events' do
          time = PgEventstore::Utils.benchmark { subject.to_a } * 1000
          # milliseconds. Keep in mind that this assertion includes performance degradation due to RBS testing
          expect(time).to be < 30
        end
      end
    end

    it { is_expected.to be_a(Enumerator) }

    context 'when there are events matching a filter' do
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

    context 'when there are no events matching the filter' do
      let(:options) { { filter: { streams: [{ context: 'NonExistingCtx' }] } } }

      it 'returns an empty array' do
        expect(subject.to_a).to eq([])
      end
    end
  end
end

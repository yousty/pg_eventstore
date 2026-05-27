# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::ReadStreamsPaginated do
  let(:instance) { described_class.new(queries) }
  let(:queries) { PgEventstore::Queries.new(streams_global_index: streams_global_index_queries) }
  let(:streams_global_index_queries) do
    PgEventstore::StreamsGlobalIndexQueries.new(
      PgEventstore.connection, PgEventstore::QueryStrategy::Foreground.new(PgEventstore.connection)
    )
  end

  describe '#call' do
    subject { instance.call(options:) }

    let(:options) { {} }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '3') }

    let!(:event1) { PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new) }
    let!(:event2) { PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new) }
    let!(:event3) { PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new) }
    let!(:event4) { PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new) }

    context 'when no options are given' do
      it 'yields all streams' do
        aggregate_failures do
          expect(subject.next).to eq([stream1, stream2, stream3])
          expect { subject.next }.to raise_error(StopIteration)
        end
      end
    end

    context 'when :max_count is given' do
      before do
        options[:max_count] = 2
      end

      it 'yields up to the given number of streams' do
        aggregate_failures do
          expect(subject.next).to eq([stream1, stream2])
          expect(subject.next).to eq([stream3])
          expect { subject.next }.to raise_error(StopIteration)
        end
      end
    end

    context 'when :direction is :desc' do
      before do
        options[:direction] = :desc
      end

      it 'yields streams in descending order' do
        aggregate_failures do
          expect(subject.next).to eq([stream3, stream2, stream1])
          expect { subject.next }.to raise_error(StopIteration)
        end
      end
    end

    context 'when :from_position is given' do
      before do
        options[:from_position] = event2.global_position
      end

      it 'yields streams, starting from that position' do
        aggregate_failures do
          expect(subject.next).to eq([stream2, stream3])
          expect { subject.next }.to raise_error(StopIteration)
        end
      end
    end
  end
end

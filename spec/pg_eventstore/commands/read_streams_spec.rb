# frozen_string_literal: true

RSpec.describe PgEventstore::Commands::ReadStreams do
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
      it 'returns all streams' do
        is_expected.to eq([stream1, stream2, stream3])
      end

      describe 'stream details' do
        it 'assigns #starting_position' do
          aggregate_failures do
            expect(subject[0].starting_position).to eq(event1.global_position)
            expect(subject[1].starting_position).to eq(event2.global_position)
            expect(subject[2].starting_position).to eq(event4.global_position)
          end
        end
        it 'assigns #stream_revision' do
          aggregate_failures do
            expect(subject[0].stream_revision).to eq(0)
            expect(subject[1].stream_revision).to eq(1)
            expect(subject[2].stream_revision).to eq(0)
          end
        end
      end
    end

    context 'when :max_count is given' do
      before do
        options[:max_count] = 2
      end

      it 'limits the result' do
        is_expected.to eq([stream1, stream2])
      end
    end

    context 'when :direction is :desc' do
      before do
        options[:direction] = :desc
      end

      it 'returns streams in descending order' do
        is_expected.to eq([stream3, stream2, stream1])
      end
    end

    context 'when :from_position is given' do
      context 'when :from_position equals #starting_position' do
        before do
          options[:from_position] = event2.global_position
        end

        it 'returns streams, starting from that position' do
          is_expected.to eq([stream2, stream3])
        end
      end

      context 'when :from_position does not equal #starting_position' do
        before do
          options[:from_position] = event3.global_position
        end

        it 'returns streams, starting after that position' do
          is_expected.to eq([stream3])
        end
      end
    end

    describe 'general read cases' do
      describe 'position at a non-starting position and direction is :desc' do
        before do
          options[:from_position] = event3.global_position
          options[:direction] = :desc
        end

        it 'returns streams, starting after that position in descending order' do
          is_expected.to eq([stream2, stream1])
        end
      end

      describe ':max_count is 1 and :from_position is at #starting_position' do
        before do
          options[:from_position] = event2.global_position
          options[:max_count] = 1
        end

        it 'returns one stream at that position' do
          is_expected.to eq([stream2])
        end
      end

      describe ':max_count == nil' do
        before do
          options[:max_count] = nil
          stub_const('PgEventstore::QueryBuilders::StreamsGlobalIndexFiltering::DEFAULT_LIMIT', 2)
        end

        it 'returns up to DEFAULT_LIMIT records' do
          is_expected.to eq([stream1, stream2])
        end
      end

      describe ':max_count is 1, :from_position is at a non-starting position, :direction is :desc' do
        before do
          options[:from_position] = event3.global_position
          options[:max_count] = 1
          options[:direction] = :desc
        end

        it 'returns one stream after that position' do
          is_expected.to eq([stream2])
        end
      end

      describe ':from_position is on a non-existing position' do
        before do
          options[:from_position] = event4.global_position + 1
        end

        it { is_expected.to eq([]) }
      end
    end
  end
end

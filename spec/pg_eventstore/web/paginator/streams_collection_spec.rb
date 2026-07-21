# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Paginator::StreamsCollection do
  let(:instance) { described_class.new(config_name, starting_id:, per_page:, order:, options:) }

  let(:config_name) { :default }
  let(:starting_id) { nil }
  let(:per_page) { 2 }
  let(:order) { :asc }
  let(:options) { {} }

  describe '#collection' do
    subject { instance.collection }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '3') }

    let!(:event1) { PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new) }
    let!(:event2) { PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new) }
    let!(:event3) { PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new) }

    describe ':asc sorting' do
      it 'returns up to per_page streams' do
        is_expected.to eq([stream1, stream2])
      end
    end

    describe ':desc sorting' do
      let(:order) { :desc }

      it 'returns up to per_page streams' do
        is_expected.to eq([stream3, stream2])
      end
    end

    context 'when :starting_id is given' do
      let(:starting_id) { event2.global_position }

      it 'returns streams from the given position' do
        is_expected.to eq([stream2, stream3])
      end
    end
  end

  describe '#next_page_starting_id' do
    subject { instance.next_page_starting_id }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '3') }

    let!(:event1) { PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new) }
    let!(:event2) { PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new) }
    let!(:event3) { PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new) }

    context 'when next page exists' do
      it 'returns its starting position' do
        is_expected.to eq(event3.global_position)
      end
    end

    context 'when next page does not exist' do
      let(:starting_id) { event2.global_position }

      it { is_expected.to eq(nil) }
    end
  end

  describe '#prev_page_starting_id' do
    subject { instance.prev_page_starting_id }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '2') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '3') }

    let!(:event1) { PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new) }
    let!(:event2) { PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new) }
    let!(:event3) { PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new) }

    context 'when prev page exists' do
      let(:starting_id) { event2.global_position }

      it 'returns its starting position' do
        is_expected.to eq(event1.global_position)
      end
    end

    context 'when prev page does not exist' do
      it { is_expected.to eq(nil) }
    end
  end

  describe '#total_count' do
    subject { instance.total_count }

    context 'when the exact count is available' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
      let!(:event) { PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new) }

      it 'returns total count' do
        is_expected.to eq(1)
      end
    end

    context 'when exact count is not available' do
      before do
        PgEventstore.client.multiple do
          10.times do |t|
            stream = PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: t.to_s)
            PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
          end
        end
        stub_const("#{described_class}::MAX_NUMBER_TO_COUNT", 1)
      end

      it 'returns estimate count' do
        is_expected.to be > 1
      end
    end
  end
end

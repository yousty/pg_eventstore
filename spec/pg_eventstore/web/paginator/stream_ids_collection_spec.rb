# frozen_string_literal: true

RSpec.describe PgEventstore::Paginator::StreamIdsCollection do
  let(:instance) do
    described_class.new(config_name, starting_id: starting_id, per_page: per_page, order: order, options: options)
  end
  let(:config_name) { :default }
  let(:starting_id) { nil }
  let(:per_page) { 2 }
  let(:order) { :asc }
  let(:options) { { context: 'FooCtx', stream_name: 'MyStream' } }

  describe '#collection' do
    subject { instance.collection }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Foo') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Fok') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Faz') }
    let(:stream4) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Bar') }
    let(:stream5) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Baz') }

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream4, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream5, PgEventstore::Event.new)
    end

    it 'returns stream ids according to the page limit and in the given order' do
      is_expected.to eq([{ 'stream_id' => 'Bar' }, { 'stream_id' => 'Baz' }])
    end

    context 'when stream with another stream name exists' do
      before do
        PgEventstore.client.append_to_stream(
          PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'MyStream', stream_id: 'Bab'), PgEventstore::Event.new
        )
      end

      it 'does not take it into account' do
        is_expected.to eq([{ 'stream_id' => 'Bar' }, { 'stream_id' => 'Baz' }])
      end
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'Baz' }

      it 'returns stream ids starting from that id' do
        is_expected.to eq([{ 'stream_id' => 'Baz' }, { 'stream_id' => 'Faz' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns stream ids starting from that id, properly ordered' do
          is_expected.to eq([{ 'stream_id' => 'Baz' }, { 'stream_id' => 'Bar' }])
        end
      end
    end

    context 'when query option is provided' do
      let(:options) { super().merge(query: 'F') }

      it 'returns stream ids, filtered by that option' do
        is_expected.to eq([{ 'stream_id' => 'Faz' }, { 'stream_id' => 'Fok' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns stream ids, filtered by that option, properly ordered' do
          is_expected.to eq([{ 'stream_id' => 'Foo' }, { 'stream_id' => 'Fok' }])
        end
      end
    end

    context 'when starting_id and query option are provided' do
      let(:starting_id) { 'Fok' }
      let(:options) { super().merge(query: 'F') }

      it 'returns stream ids, filtered by that query option, starting from the given id' do
        is_expected.to eq([{ 'stream_id' => 'Fok' }, { 'stream_id' => 'Foo' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns stream ids, filtered by that query option, starting from the given id, properly ordered' do
          is_expected.to eq([{ 'stream_id' => 'Fok' }, { 'stream_id' => 'Faz' }])
        end
      end
    end
  end

  describe '#next_page_starting_id' do
    subject { instance.next_page_starting_id }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Foo') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Fok') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Faz') }
    let(:stream4) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Bar') }
    let(:stream5) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'MyStream', stream_id: 'Baz') }

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream4, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream5, PgEventstore::Event.new)
    end

    it 'returns starting id of next page' do
      is_expected.to eq('Faz')
    end

    context 'when stream with the same name, but with other context exists' do
      before do
        PgEventstore.client.append_to_stream(
          PgEventstore::Stream.new(context: 'BasCtx', stream_name: 'MyStream', stream_id: 'Bas'),
          PgEventstore::Event.new
        )
      end

      it 'does not take it into account' do
        is_expected.to eq('Faz')
      end
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'Baz' }

      it 'returns starting id of next page, relative to that id' do
        is_expected.to eq('Fok')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'Foo' }

        it 'returns starting id of next page, relative to that id, in reversed order' do
          is_expected.to eq('Faz')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'Fok' }

        it { is_expected.to eq(nil) }
      end
    end

    context 'when query option is provided' do
      let(:options) { super().merge(query: 'F') }

      it 'returns starting id of next page, based on the query filter' do
        is_expected.to eq('Foo')
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns starting id of next page, based on the query filter and the order' do
          is_expected.to eq('Faz')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'Fok' }

        it { is_expected.to eq(nil) }
      end
    end

    context 'when starting_id and query option are provided' do
      let(:starting_id) { 'Faz' }
      let(:options) { super().merge(query: 'F') }

      it 'returns starting id of the next page based on the given starting_id and query option' do
        is_expected.to eq('Foo')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'Foo' }

        it 'returns starting id of the next page based on the given starting_id and query option, in revered order' do
          is_expected.to eq('Faz')
        end
      end

      context 'when there is no more pages after the given starting_id by the given filter' do
        let(:starting_id) { 'Fok' }

        it { is_expected.to eq(nil) }
      end
    end
  end
end

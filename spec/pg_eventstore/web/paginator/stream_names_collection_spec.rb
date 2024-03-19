# frozen_string_literal: true

RSpec.describe PgEventstore::Paginator::StreamNamesCollection do
  let(:instance) do
    described_class.new(config_name, starting_id: starting_id, per_page: per_page, order: order, options: options)
  end
  let(:config_name) { :default }
  let(:starting_id) { nil }
  let(:per_page) { 2 }
  let(:order) { :asc }
  let(:options) { { context: 'FooCtx' } }

  describe '#collection' do
    subject { instance.collection }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Fok', stream_id: '1') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Faz', stream_id: '1') }
    let(:stream4) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
    let(:stream5) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Baz', stream_id: '1') }

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream4, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream5, PgEventstore::Event.new)
    end

    it 'returns stream names according to the page limit and in the given order' do
      is_expected.to eq([{ 'stream_name' => 'Bar' }, { 'stream_name' => 'Baz' }])
    end

    context 'when stream from another context exists' do
      before do
        PgEventstore.client.append_to_stream(
          PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bab', stream_id: '1'), PgEventstore::Event.new
        )
      end

      it 'does not take it into account' do
        is_expected.to eq([{ 'stream_name' => 'Bar' }, { 'stream_name' => 'Baz' }])
      end
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'Baz' }

      it 'returns stream names starting from that id' do
        is_expected.to eq([{ 'stream_name' => 'Baz' }, { 'stream_name' => 'Faz' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns stream names starting from that id, properly ordered' do
          is_expected.to eq([{ 'stream_name' => 'Baz' }, { 'stream_name' => 'Bar' }])
        end
      end
    end

    context 'when query option is provided' do
      let(:options) { super().merge(query: 'F') }

      it 'returns stream names, filtered by that option' do
        is_expected.to eq([{ 'stream_name' => 'Faz' }, { 'stream_name' => 'Fok' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns stream names, filtered by that option, properly ordered' do
          is_expected.to eq([{ 'stream_name' => 'Foo' }, { 'stream_name' => 'Fok' }])
        end
      end
    end

    context 'when starting_id and query option are provided' do
      let(:starting_id) { 'Fok' }
      let(:options) { super().merge(query: 'F') }

      it 'returns stream names, filtered by that query option, starting from the given id' do
        is_expected.to eq([{ 'stream_name' => 'Fok' }, { 'stream_name' => 'Foo' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns stream names, filtered by that query option, starting from the given id, properly ordered' do
          is_expected.to eq([{ 'stream_name' => 'Fok' }, { 'stream_name' => 'Faz' }])
        end
      end
    end
  end

  describe '#next_page_starting_id' do
    subject { instance.next_page_starting_id }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Fok', stream_id: '1') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Faz', stream_id: '1') }
    let(:stream4) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Bar', stream_id: '1') }
    let(:stream5) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Baz', stream_id: '1') }

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

    context 'when stream from another context exists' do
      before do
        PgEventstore.client.append_to_stream(
          PgEventstore::Stream.new(context: 'BasCtx', stream_name: 'Bas', stream_id: '1'), PgEventstore::Event.new
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

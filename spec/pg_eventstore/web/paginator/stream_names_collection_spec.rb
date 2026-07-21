# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Paginator::StreamNamesCollection do
  let(:instance) do
    described_class.new(config_name, starting_id:, per_page:, order:, options:)
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
    let(:stream6) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'foo', stream_id: '1') }
    let(:stream7) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'fok', stream_id: '1') }
    let(:stream8) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'barfoo', stream_id: '1') }

    before do
      events = Array.new(2) { PgEventstore::Event.new }
      PgEventstore.client.append_to_stream(stream1, events)
      PgEventstore.client.append_to_stream(stream2, events)
      PgEventstore.client.append_to_stream(stream3, events)
      PgEventstore.client.append_to_stream(stream4, events)
      PgEventstore.client.append_to_stream(stream5, events)
      PgEventstore.client.append_to_stream(stream6, events)
      PgEventstore.client.append_to_stream(stream7, events)
      PgEventstore.client.append_to_stream(stream8, events)
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
      before do
        # A stream from another context. It is used to ensure proper filtering by context under different filter options
        PgEventstore.client.append_to_stream(
          PgEventstore::Stream.new(context: '', stream_name: 'foo', stream_id: '1'),
          PgEventstore::Event.new
        )
      end

      context 'when query length is less than 3 symbols' do
        let(:options) { super().merge(query: 'f') }

        it 'returns case-sensitive result that starts from the given filter' do
          is_expected.to eq([{ 'stream_name' => 'fok' }, { 'stream_name' => 'foo' }])
        end

        context 'when order is :desc' do
          let(:order) { :desc }

          it 'returns contexts, filtered by that option, properly ordered' do
            is_expected.to eq([{ 'stream_name' => 'foo' }, { 'stream_name' => 'fok' }])
          end
        end
      end

      context 'when query length is gte 3 symbols' do
        let(:options) { super().merge(query: 'foo') }

        it 'returns case-insensitive result, filtered by any part of the word by the given filter' do
          is_expected.to eq([{ 'stream_name' => 'Foo' }, { 'stream_name' => 'barfoo' }])
        end

        context 'when order is :desc' do
          let(:order) { :desc }

          it 'returns contexts, filtered by that option, properly ordered' do
            is_expected.to eq([{ 'stream_name' => 'foo' }, { 'stream_name' => 'barfoo' }])
          end
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

    let(:streams) do
      [
        PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'FooFoo', stream_id: '1'),
        PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'FooFok', stream_id: '1'),
        PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'FooFaz', stream_id: '1'),
        PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'BarBar', stream_id: '1'),
        PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'BarBaz', stream_id: '1'),
        PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'BarBom', stream_id: '1'),
      ]
    end

    before do
      streams.each do |stream|
        PgEventstore.client.append_to_stream(stream, PgEventstore::Event.new)
      end
    end

    it 'returns starting id of next page' do
      is_expected.to eq('BarBom')
    end

    context 'when stream from another context exists' do
      before do
        PgEventstore.client.append_to_stream(
          PgEventstore::Stream.new(context: 'BasCtx', stream_name: 'BarBas', stream_id: '1'), PgEventstore::Event.new
        )
      end

      it 'does not take it into account' do
        is_expected.to eq('BarBom')
      end
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'BarBaz' }

      it 'returns starting id of next page, relative to that id' do
        is_expected.to eq('FooFaz')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'FooFoo' }

        it 'returns starting id of next page, relative to that id, in reversed order' do
          is_expected.to eq('FooFaz')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'FooFok' }

        it { is_expected.to eq(nil) }
      end
    end

    context 'when query option is provided' do
      let(:options) { super().merge(query: 'F') }

      it 'returns starting id of next page, based on the query filter' do
        is_expected.to eq('FooFoo')
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns starting id of next page, based on the query filter and the order' do
          is_expected.to eq('FooFaz')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'FooFok' }

        it { is_expected.to eq(nil) }
      end

      context 'when query matches a substring in the middle of the word' do
        context 'when query length is less than 3 symbols' do
          let(:options) { super().merge(query: 'a') }

          it 'does not recognize it' do
            is_expected.to eq(nil)
          end
        end

        context 'when query length is gte 3 symbols' do
          let(:options) { super().merge(query: 'oof') }

          it 'recognizes it' do
            is_expected.to eq('FooFoo')
          end
        end
      end
    end

    context 'when starting_id and query option are provided' do
      let(:starting_id) { 'FooFaz' }
      let(:options) { super().merge(query: 'F') }

      it 'returns starting id of the next page based on the given starting_id and query option' do
        is_expected.to eq('FooFoo')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'FooFoo' }

        it 'returns starting id of the next page based on the given starting_id and query option, in revered order' do
          is_expected.to eq('FooFaz')
        end
      end

      context 'when there is no more pages after the given starting_id by the given filter' do
        let(:starting_id) { 'FooFok' }

        it { is_expected.to eq(nil) }
      end

      context 'when query matches a substring in the middle of the word' do
        let(:starting_id) { 'BarBar' }

        context 'when query length is less than 3 symbols' do
          let(:options) { super().merge(query: 'a') }

          it 'does not recognize it' do
            is_expected.to eq(nil)
          end
        end

        context 'when query length is gte 3 symbols' do
          let(:options) { super().merge(query: 'arb') }

          it 'recognizes it' do
            is_expected.to eq('BarBom')
          end
        end
      end
    end
  end
end

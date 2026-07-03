# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Paginator::StreamContextsCollection do
  let(:instance) do
    described_class.new(config_name, starting_id:, per_page:, order:, options:)
  end
  let(:config_name) { :default }
  let(:starting_id) { nil }
  let(:per_page) { 2 }
  let(:order) { :asc }
  let(:options) { {} }

  describe '#collection' do
    subject { instance.collection }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FokCtx', stream_name: 'Fok', stream_id: '1') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FazCtx', stream_name: 'Faz', stream_id: '1') }
    let(:stream4) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }
    let(:stream5) { PgEventstore::Stream.new(context: 'BazCtx', stream_name: 'Baz', stream_id: '1') }
    let(:stream6) { PgEventstore::Stream.new(context: 'fooCtx', stream_name: 'foo', stream_id: '1') }
    let(:stream7) { PgEventstore::Stream.new(context: 'fokCtx', stream_name: 'foo', stream_id: '1') }
    let(:stream8) { PgEventstore::Stream.new(context: 'barfooCtx', stream_name: 'foo', stream_id: '1') }

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

    it 'returns contexts according to the page limit and in the given order' do
      is_expected.to eq([{ 'context' => 'BarCtx' }, { 'context' => 'BazCtx' }])
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'BazCtx' }

      it 'returns contexts starting from that id' do
        is_expected.to eq([{ 'context' => 'BazCtx' }, { 'context' => 'FazCtx' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns contexts starting from that id, properly ordered' do
          is_expected.to eq([{ 'context' => 'BazCtx' }, { 'context' => 'BarCtx' }])
        end
      end
    end

    context 'when query option is provided' do
      context 'when query length is less than 3 symbols' do
        let(:options) { { query: 'f' } }

        it 'returns case-sensitive result that starts from the given filter' do
          is_expected.to eq([{ 'context' => 'fokCtx' }, { 'context' => 'fooCtx' }])
        end

        context 'when order is :desc' do
          let(:order) { :desc }

          it 'returns contexts, filtered by that option, properly ordered' do
            is_expected.to eq([{ 'context' => 'fooCtx' }, { 'context' => 'fokCtx' }])
          end
        end
      end

      context 'when query length is gte 3 symbols' do
        let(:options) { { query: 'foo' } }

        it 'returns case-insensitive result, filtered by any part of the word by the given filter' do
          is_expected.to eq([{ 'context' => 'FooCtx' }, { 'context' => 'barfooCtx' }])
        end

        context 'when order is :desc' do
          let(:order) { :desc }

          it 'returns contexts, filtered by that option, properly ordered' do
            is_expected.to eq([{ 'context' => 'fooCtx' }, { 'context' => 'barfooCtx' }])
          end
        end
      end
    end

    context 'when starting_id and query option are provided' do
      let(:starting_id) { 'FokCtx' }
      let(:options) { { query: 'F' } }

      it 'returns contexts, filtered by that query option, starting from the given id' do
        is_expected.to eq([{ 'context' => 'FokCtx' }, { 'context' => 'FooCtx' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns contexts, filtered by that query option, starting from the given id, properly ordered' do
          is_expected.to eq([{ 'context' => 'FokCtx' }, { 'context' => 'FazCtx' }])
        end
      end
    end
  end

  describe '#next_page_starting_id' do
    subject { instance.next_page_starting_id }

    let(:stream1) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }
    let(:stream2) { PgEventstore::Stream.new(context: 'FokCtx', stream_name: 'Fok', stream_id: '1') }
    let(:stream3) { PgEventstore::Stream.new(context: 'FazCtx', stream_name: 'Faz', stream_id: '1') }
    let(:stream4) { PgEventstore::Stream.new(context: 'BarCtx', stream_name: 'Bar', stream_id: '1') }
    let(:stream5) { PgEventstore::Stream.new(context: 'BazCtx', stream_name: 'Baz', stream_id: '1') }

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream4, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream5, PgEventstore::Event.new)
    end

    it 'returns starting id of next page' do
      is_expected.to eq('FazCtx')
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'BazCtx' }

      it 'returns starting id of next page, relative to that id' do
        is_expected.to eq('FokCtx')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'FooCtx' }

        it 'returns starting id of next page, relative to that id, in reversed order' do
          is_expected.to eq('FazCtx')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'FokCtx' }

        it { is_expected.to eq(nil) }
      end
    end

    context 'when query option is provided' do
      let(:options) { { query: 'F' } }

      it 'returns starting id of next page, based on the query filter' do
        is_expected.to eq('FooCtx')
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns starting id of next page, based on the query filter and the order' do
          is_expected.to eq('FazCtx')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'FokCtx' }

        it { is_expected.to eq(nil) }
      end

      context 'when query matches a substring in the middle of the word' do
        context 'when query length is less than 3 symbols' do
          let(:options) { { query: 'a' } }

          it 'does not recognize it' do
            is_expected.to eq(nil)
          end
        end

        context 'when query length is gte 3 symbols' do
          let(:options) { { query: 'ctx' } }

          it 'recognizes it' do
            is_expected.to eq('FazCtx')
          end
        end
      end
    end

    context 'when starting_id and query option are provided' do
      let(:starting_id) { 'FazCtx' }
      let(:options) { { query: 'F' } }

      it 'returns starting id of the next page based on the given starting_id and query option' do
        is_expected.to eq('FooCtx')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'FooCtx' }

        it 'returns starting id of the next page based on the given starting_id and query option, in revered order' do
          is_expected.to eq('FazCtx')
        end
      end

      context 'when there is no more pages after the given starting_id by the given filter' do
        let(:starting_id) { 'FokCtx' }

        it { is_expected.to eq(nil) }
      end

      context 'when query matches a substring in the middle of the word' do
        let(:starting_id) { 'BarCtx' }

        context 'when query length is less than 3 symbols' do
          let(:options) { { query: 'a' } }

          it 'does not recognize it' do
            is_expected.to eq(nil)
          end
        end

        context 'when query length is gte 3 symbols' do
          let(:options) { { query: 'ctx' } }

          it 'recognizes it' do
            is_expected.to eq('FazCtx')
          end
        end
      end
    end
  end
end

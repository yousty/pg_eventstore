# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Paginator::StreamContextsCollection do
  let(:instance) do
    described_class.new(config_name, starting_id: starting_id, per_page: per_page, order: order, options: options)
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

    before do
      PgEventstore.client.append_to_stream(stream1, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream2, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream3, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream4, PgEventstore::Event.new)
      PgEventstore.client.append_to_stream(stream5, PgEventstore::Event.new)
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
      let(:options) { { query: 'F' } }

      it 'returns contexts, filtered by that option' do
        is_expected.to eq([{ 'context' => 'FazCtx' }, { 'context' => 'FokCtx' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns contexts, filtered by that option, properly ordered' do
          is_expected.to eq([{ 'context' => 'FooCtx' }, { 'context' => 'FokCtx' }])
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
    end
  end
end

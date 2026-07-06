# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Paginator::MarkersCollection do
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

    let!(:events) do
      events = [
        PgEventstore::Event.new(markers: ['foo']),
        PgEventstore::Event.new(markers: ['fok']),
        PgEventstore::Event.new(markers: ['faz']),
        PgEventstore::Event.new(markers: ['bar']),
        PgEventstore::Event.new(markers: ['baz']),
      ]
      PgEventstore.client.append_to_stream(stream, events)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    it 'returns markers according to the page limit and in the given order' do
      is_expected.to eq([{ 'name' => 'bar' }, { 'name' => 'baz' }])
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'baz' }

      it 'returns markers starting from that id' do
        is_expected.to eq([{ 'name' => 'baz' }, { 'name' => 'faz' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns markers starting from that id, properly ordered' do
          is_expected.to eq([{ 'name' => 'baz' }, { 'name' => 'bar' }])
        end
      end
    end

    context 'when query option is provided' do
      let(:options) { { query: 'f' } }

      it 'returns markers, filtered by that option' do
        is_expected.to eq([{ 'name' => 'faz' }, { 'name' => 'fok' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns markers, filtered by that option, properly ordered' do
          is_expected.to eq([{ 'name' => 'foo' }, { 'name' => 'fok' }])
        end
      end
    end

    context 'when starting_id and query option is provided' do
      let(:starting_id) { 'fok' }
      let(:options) { { query: 'f' } }

      it 'returns markers, filtered by that query option, starting from the given id' do
        is_expected.to eq([{ 'name' => 'fok' }, { 'name' => 'foo' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns markers, filtered by that query option, starting from the given id, properly ordered' do
          is_expected.to eq([{ 'name' => 'fok' }, { 'name' => 'faz' }])
        end
      end
    end
  end

  describe '#next_page_starting_id' do
    subject { instance.next_page_starting_id }

    let!(:events) do
      events = [
        PgEventstore::Event.new(markers: ['foo']),
        PgEventstore::Event.new(markers: ['fok']),
        PgEventstore::Event.new(markers: ['faz']),
        PgEventstore::Event.new(markers: ['bar']),
        PgEventstore::Event.new(markers: ['baz']),
      ]
      PgEventstore.client.append_to_stream(stream, events)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    it 'returns starting id of next page' do
      is_expected.to eq('faz')
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'baz' }

      it 'returns starting id of next page, relative to that id' do
        is_expected.to eq('fok')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'foo' }

        it 'returns starting id of next page, relative to that id, in reversed order' do
          is_expected.to eq('faz')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'fok' }

        it { is_expected.to eq(nil) }
      end
    end

    context 'when query option is provided' do
      let(:options) { { query: 'f' } }

      it 'returns starting id of next page, based on the query filter' do
        is_expected.to eq('foo')
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns starting id of next page, based on the query filter and the order' do
          is_expected.to eq('faz')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'fok' }

        it { is_expected.to eq(nil) }
      end
    end

    context 'when starting_id and query option are provided' do
      let(:starting_id) { 'faz' }
      let(:options) { { query: 'f' } }

      it 'returns starting id of the next page based on the given starting_id and query option' do
        is_expected.to eq('foo')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'foo' }

        it 'returns starting id of the next page based on the given starting_id and query option, in revered order' do
          is_expected.to eq('faz')
        end
      end

      context 'when there is no more pages after the given starting_id by the given filter' do
        let(:starting_id) { 'fok' }

        it { is_expected.to eq(nil) }
      end
    end
  end
end

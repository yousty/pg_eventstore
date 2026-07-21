# frozen_string_literal: true

RSpec.describe PgEventstore::Web::Paginator::EventTypesCollection do
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
        PgEventstore::Event.new(type: 'foofoo'),
        PgEventstore::Event.new(type: 'fokfok'),
        PgEventstore::Event.new(type: 'FazFaz'),
        PgEventstore::Event.new(type: 'barbar'),
        PgEventstore::Event.new(type: 'bazbaz'),
      ]
      PgEventstore.client.append_to_stream(stream, events)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    it 'returns event types according to the page limit and in the given order' do
      is_expected.to eq([{ 'event_type' => 'FazFaz' }, { 'event_type' => 'barbar' }])
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'bazbaz' }

      it 'returns event types starting from that id' do
        is_expected.to eq([{ 'event_type' => 'bazbaz' }, { 'event_type' => 'fokfok' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns event types starting from that id, properly ordered' do
          is_expected.to eq([{ 'event_type' => 'bazbaz' }, { 'event_type' => 'barbar' }])
        end
      end
    end

    context 'when query option is provided' do
      let(:options) { { query: 'f' } }

      it 'returns event types, filtered by that option' do
        is_expected.to eq([{ 'event_type' => 'fokfok' }, { 'event_type' => 'foofoo' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns event types, filtered by that option, properly ordered' do
          is_expected.to eq([{ 'event_type' => 'foofoo' }, { 'event_type' => 'fokfok' }])
        end
      end

      context 'when query length is less than 3 symbols' do
        describe 'beginning of the word' do
          let(:options) { { query: 'F' } }

          it 'performs case-sensitive search' do
            is_expected.to eq([{ 'event_type' => 'FazFaz' }])
          end
        end

        describe 'search by middle of the word' do
          let(:options) { { query: 'zF' } }

          it 'ignores it' do
            is_expected.to eq([])
          end
        end
      end

      context 'when query length is gte 3 symbols' do
        let(:options) { { query: 'azf' } }

        it 'performs case-insensitive search by any part of the word' do
          is_expected.to eq([{ 'event_type' => 'FazFaz' }])
        end
      end
    end

    context 'when starting_id and query option is provided' do
      let(:starting_id) { 'fokfok' }
      let(:options) { { query: 'f' } }

      it 'returns event types, filtered by that query option, starting from the given id' do
        is_expected.to eq([{ 'event_type' => 'fokfok' }, { 'event_type' => 'foofoo' }])
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns event types, filtered by that query option, starting from the given id, properly ordered' do
          is_expected.to eq([{ 'event_type' => 'fokfok' }])
        end
      end
    end
  end

  describe '#next_page_starting_id' do
    subject { instance.next_page_starting_id }

    let!(:events) do
      events = [
        PgEventstore::Event.new(type: 'foobar'),
        PgEventstore::Event.new(type: 'foofok'),
        PgEventstore::Event.new(type: 'foofoo'),
        PgEventstore::Event.new(type: 'foofaz'),
        PgEventstore::Event.new(type: 'FazFaz'),
        PgEventstore::Event.new(type: 'barbar'),
        PgEventstore::Event.new(type: 'bazbaz'),
        PgEventstore::Event.new(type: 'zzz'),
      ]
      PgEventstore.client.append_to_stream(stream, events)
    end
    let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    it 'returns starting id of next page' do
      is_expected.to eq('bazbaz')
    end

    context 'when starting_id is given' do
      let(:starting_id) { 'bazbaz' }

      it 'returns starting id of next page, relative to that id' do
        is_expected.to eq('foofaz')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'foofoo' }

        it 'returns starting id of next page, relative to that id, in reversed order' do
          is_expected.to eq('foofaz')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'foofoo' }

        it { is_expected.to eq(nil) }
      end
    end

    context 'when query option is provided' do
      let(:options) { { query: 'f' } }

      it 'returns starting id of next page, based on the query filter' do
        is_expected.to eq('foofok')
      end

      context 'when order is :desc' do
        let(:order) { :desc }

        it 'returns starting id of next page, based on the query filter and the order' do
          is_expected.to eq('foofaz')
        end
      end

      context 'when there is no more pages after the given starting_id' do
        let(:starting_id) { 'foofok' }

        it { is_expected.to eq(nil) }
      end

      context 'when query matches a substring in the middle of the word' do
        let(:options) { { query: 'a' } }

        context 'when query length is less than 3 symbols' do
          it 'does not recognize it' do
            is_expected.to eq(nil)
          end
        end

        context 'when query length is gte 3 symbols' do
          let(:options) { { query: 'oof' } }

          it 'recognize it' do
            is_expected.to eq('foofoo')
          end
        end
      end
    end

    context 'when starting_id and query option are provided' do
      let(:starting_id) { 'foobar' }
      let(:options) { { query: 'f' } }

      it 'returns starting id of the next page based on the given starting_id and query option' do
        is_expected.to eq('foofok')
      end

      context 'when order is :desc' do
        let(:order) { :desc }
        let(:starting_id) { 'foofoo' }

        it 'returns starting id of the next page based on the given starting_id and query option, in revered order' do
          is_expected.to eq('foofaz')
        end
      end

      context 'when there is no more pages after the given starting_id by the given filter' do
        let(:starting_id) { 'foofoo' }

        it { is_expected.to eq(nil) }
      end

      context 'when query matches a substring in the middle of the word' do
        let(:starting_id) { 'foofaz' }

        context 'when query length is less than 3 symbols' do
          let(:options) { { query: 'a' } }

          it 'does not recognize it' do
            is_expected.to eq(nil)
          end
        end

        context 'when query length is gte 3 symbols' do
          let(:options) { { query: 'oof' } }

          it 'recognizes it' do
            is_expected.to eq('foofoo')
          end
        end
      end
    end
  end
end

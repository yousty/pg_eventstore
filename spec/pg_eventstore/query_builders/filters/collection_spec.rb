# frozen_string_literal: true

RSpec.describe PgEventstore::QueryBuilders::Filters::Collection do
  shared_examples 'empty collection' do
    it { is_expected.to be_empty.and be_a(described_class) }
  end

  describe '.from_stream_and_options' do
    subject { described_class.from_stream_and_options(stream, options) }

    let(:stream) { PgEventstore::Stream.all_stream }
    let(:options) { {} }

    context 'when stream is "all" stream' do
      context 'when options are empty' do
        it_behaves_like 'empty collection'
      end

      context 'when options are present' do
        let(:options) { { filter: { event_types: ['Foo'], streams: [{ context: 'FooCtx' }] } } }

        it 'construct proper collection' do
          event_type_filters = [
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo'),
          ]
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx'),
            event_type_filters: event_type_filters
          )
          expect(subject.collection).to eq([filter_row])
        end
      end
    end

    context 'when stream is a regular stream' do
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

      context 'when options are empty' do
        it 'constructs collection from the given stream' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(
              context: 'FooCtx', stream_name: 'Foo', stream_id: '1'
            ),
            event_type_filters: []
          )
          expect(subject.collection).to eq([filter_row])
        end
      end

      context 'when event types filter is given' do
        let(:options) { { filter: { event_types: ['Foo'] } } }

        it 'constructs collection from the given stream and event types' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(
              context: 'FooCtx', stream_name: 'Foo', stream_id: '1'
            ),
            event_type_filters: [
              PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo'),
            ]
          )
          expect(subject.collection).to eq([filter_row])
        end
      end

      context 'when stream filter is given' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }] } } }

        it 'ignores it' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(
              context: 'FooCtx', stream_name: 'Foo', stream_id: '1'
            ),
            event_type_filters: []
          )
          expect(subject.collection).to eq([filter_row])
        end
      end
    end
  end

  describe '#from_options' do
    subject { described_class.from_options(options) }

    let(:options) { {} }

    context 'when correct event types filter is provided' do
      let(:options) { { filter: { event_types: %w[Foo Bar] } } }

      it 'recognizes it' do
        filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: nil,
          event_type_filters: [
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo'),
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Bar'),
          ]
        )
        expect(subject.collection).to eq([filter_row])
      end
    end

    context 'when "prefix" event types filter is provided' do
      let(:options) { { filter: { event_types: ['Foo', { prefix: 'Bar' }] } } }

      it 'recognizes it' do
        filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: nil,
          event_type_filters: [
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo'),
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, value: 'Bar'),
          ]
        )
        expect(subject.collection).to eq([filter_row])
      end
    end

    context 'when one of event types filter values is nil' do
      let(:options) { { filter: { event_types: ['Foo', nil] } } }

      it 'ignores it' do
        filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: nil,
          event_type_filters: [
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo'),
          ]
        )
        expect(subject.collection).to eq([filter_row])
      end
    end

    context 'when incorrect event types filter is provided' do
      let(:options) { { filter: { event_types: {} } } }

      it_behaves_like 'empty collection'
    end

    context 'when correct streams filter is provided' do
      let(:options) do
        {
          filter: {
            streams: [
              { context: 'FooCtx' },
              { context: 'BarCtx', stream_name: 'Bar' },
              { context: 'BazCtx', stream_name: 'Baz', stream_id: '1' },
            ],
          },
        }
      end

      it 'recognizes it' do
        filter_row1 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx'),
          event_type_filters: []
        )
        filter_row2 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(
            context: 'BarCtx', stream_name: 'Bar'
          ),
          event_type_filters: []
        )
        filter_row3 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(
            context: 'BazCtx', stream_name: 'Baz', stream_id: '1'
          ),
          event_type_filters: []
        )
        expect(subject.collection).to eq([filter_row1, filter_row2, filter_row3])
      end
    end

    context 'when one of streams filter values does not satisfy filtering rules' do
      shared_examples 'ignoring incorrect streams filter' do
        it 'ignores it' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx'),
            event_type_filters: []
          )
          expect(subject.collection).to eq([filter_row])
        end
      end

      context 'when incorrect filter contains :stream_name only criteria' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }, { stream_name: 'Foo' }] } } }

        it_behaves_like 'ignoring incorrect streams filter'
      end

      context 'when incorrect filter contains :stream_id only criteria' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }, { stream_id: '1' }] } } }

        it_behaves_like 'ignoring incorrect streams filter'
      end

      context 'when incorrect filter contains :stream_name and :stream_id criteria' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }, { stream_name: 'Foo', stream_id: '1' }] } } }

        it_behaves_like 'ignoring incorrect streams filter'
      end

      context 'when incorrect filter contains nil value criteria' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }, { context: nil }] } } }

        it_behaves_like 'ignoring incorrect streams filter'
      end

      context 'when incorrect filter is nil' do
        let(:options) { { filter: { streams: [{ context: 'FooCtx' }, nil] } } }

        it_behaves_like 'ignoring incorrect streams filter'
      end
    end

    context 'when streams filter is incorrect' do
      let(:options) { { filter: { streams: {} } } }

      it_behaves_like 'empty collection'
    end

    context 'when some streams filter criteria are nil' do
      let(:options) do
        {
          filter: {
            streams: [
              { context: 'FooCtx' },
              { context: 'BarCtx', stream_name: nil },
              { context: 'BazCtx', stream_name: 'Baz', stream_id: nil },
            ],
          },
        }
      end

      it 'strips nil values and keeps the rest' do
        filter_row1 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx'),
          event_type_filters: []
        )
        filter_row2 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'BarCtx'),
          event_type_filters: []
        )
        filter_row3 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(
            context: 'BazCtx', stream_name: 'Baz'
          ),
          event_type_filters: []
        )
        expect(subject.collection).to eq([filter_row1, filter_row2, filter_row3])
      end
    end

    context 'when streams and event types are given' do
      let(:options) do
        {
          filter: {
            streams: [
              { context: 'FooCtx' },
              { context: 'BarCtx' },
            ],
            event_types: %w[Foo Bar],
          },
        }
      end

      it 'recognizes them' do
        event_type_filters = [
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo'),
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Bar'),
        ]
        filter_row1 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx'),
          event_type_filters: event_type_filters
        )
        filter_row2 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'BarCtx'),
          event_type_filters: event_type_filters
        )
        expect(subject.collection).to eq([filter_row1, filter_row2])
      end
    end
  end

  describe '#collection' do
    subject { instance.collection }

    let(:instance) { described_class.new }

    context 'when #collection was not called before' do
      it 'compiles the collection' do
        expect { subject }.to change { instance.instance_variable_get(:@compiled).__id__ }
      end
    end

    context 'when #collection was called before' do
      before do
        instance.collection
      end

      it 'does not compile the collection again' do
        expect { subject }.not_to change { instance.instance_variable_get(:@compiled).__id__ }
      end
    end

    describe 'filters combination' do
      before do
        instance.add_event_type(PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo'))
        instance.add_event_type(PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, value: 'Bar'))
        instance.add_stream(PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx'))
        instance.add_stream(PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'BarCtx'))
      end

      it 'returns FilterRow-s - combinations of streams and event types filters' do
        event_type_filters = [
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo'),
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, value: 'Bar'),
        ]
        filter_row1 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx'),
          event_type_filters: event_type_filters
        )
        filter_row2 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'BarCtx'),
          event_type_filters: event_type_filters
        )
        is_expected.to eq([filter_row1, filter_row2])
      end
    end

    context 'when overlapping filters are given' do
      context 'when filters overlap by context' do
        before do
          instance.add_stream(PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx'))
          instance.add_stream(
            PgEventstore::QueryBuilders::Filters::StreamFilter.new(
              context: 'FooCtx', stream_name: 'Foo'
            )
          )
        end

        it 'keeps more general one' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx'),
            event_type_filters: []
          )
          is_expected.to eq([filter_row])
        end
      end

      context 'when filters overlap by stream_name' do
        before do
          instance.add_stream(
            PgEventstore::QueryBuilders::Filters::StreamFilter.new(
              context: 'FooCtx', stream_name: 'Foo'
            )
          )
          instance.add_stream(
            PgEventstore::QueryBuilders::Filters::StreamFilter.new(
              context: 'FooCtx', stream_name: 'Foo', stream_id: '1'
            )
          )
        end

        it 'keeps more general one' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            stream_filter: PgEventstore::QueryBuilders::Filters::StreamFilter.new(
              context: 'FooCtx', stream_name: 'Foo'
            ),
            event_type_filters: []
          )
          is_expected.to eq([filter_row])
        end
      end
    end
  end

  describe '#add_stream' do
    subject { instance.add_stream(stream_filter) }

    let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }
    let(:instance) { described_class.new }

    context 'when collection is already compiled' do
      before do
        instance.collection
      end

      it 'resets it' do
        expect { subject }.to change { instance.instance_variable_get(:@compiled) }.to(nil)
      end
    end

    context 'when the given filter is already added' do
      before do
        instance.add_stream(stream_filter)
      end

      it 'does not add another one' do
        expect { subject }.not_to change { instance.collection }
      end
    end

    context 'when the given filter is not added yet' do
      it 'adds it' do
        filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: stream_filter,
          event_type_filters: []
        )
        expect { subject }.to change { instance.collection }.to([filter_row])
      end
    end
  end

  describe '#add_event_type' do
    subject { instance.add_event_type(event_type_filter) }

    let(:event_type_filter) { PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: false) }
    let(:instance) { described_class.new }

    context 'when collection is already compiled' do
      before do
        instance.collection
      end

      it 'resets it' do
        expect { subject }.to change { instance.instance_variable_get(:@compiled) }.to(nil)
      end
    end

    context 'when the given filter is already added' do
      before do
        instance.add_event_type(event_type_filter)
      end

      it 'does not add another one' do
        expect { subject }.not_to change { instance.collection }
      end
    end

    context 'when the given filter is not added yet' do
      it 'adds it' do
        filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: nil,
          event_type_filters: [event_type_filter]
        )
        expect { subject }.to change { instance.collection }.to([filter_row])
      end

      context 'when event type filter is a prefix filter' do
        let(:event_type_filter) do
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: true)
        end

        it 'marks instance as the one having a prefix filter' do
          expect { subject }.to change { instance.has_prefix_filter? }.to(true)
        end
      end

      context 'when event type filter is not a prefix filter' do
        it 'does not change prefix filter flag' do
          expect { subject }.not_to change { instance.has_prefix_filter? }
        end
      end

      context 'when event adding non-prefix filter after prefix filter was added' do
        let(:another_event_type_filter) do
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Bar', prefix: true)
        end

        before do
          instance.add_event_type(another_event_type_filter)
        end

        it 'does not change prefix filter flag' do
          expect { subject }.not_to change { instance.has_prefix_filter? }.from(true)
        end
      end
    end
  end

  describe '#has_event_types?' do
    subject { instance.has_event_types? }

    let(:instance) { described_class.new }

    describe 'when collection contains event type filter' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: false)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(true) }
    end

    describe 'when collection contains stream filter' do
      let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

      before do
        instance.add_stream(stream_filter)
      end

      it { is_expected.to eq(false) }
    end

    describe 'when collection is empty' do
      it { is_expected.to eq(false) }
    end
  end

  describe '#empty?' do
    subject { instance.empty? }

    let(:instance) { described_class.new }

    describe 'when collection contains event type filter' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: false)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(false) }
    end

    describe 'when collection contains stream filter' do
      let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

      before do
        instance.add_stream(stream_filter)
      end

      it { is_expected.to eq(false) }
    end

    describe 'when collection is empty' do
      it { is_expected.to eq(true) }
    end
  end

  describe '#has_prefix_filter?' do
    subject { instance.has_prefix_filter? }

    let(:instance) { described_class.new }

    describe 'when collection contains non-prefix event type filter' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: false)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(false) }
    end

    describe 'when collection contains prefix event type filter' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: true)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(true) }
    end

    describe 'when collection contains stream filter' do
      let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

      before do
        instance.add_stream(stream_filter)
      end

      it { is_expected.to eq(false) }
    end

    describe 'when collection is empty' do
      it { is_expected.to eq(false) }
    end
  end
end

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
        let(:options) do
          {
            filter: {
              event_types: ['Foo', { type: 'Bar', markers: %w[foo bar] }, markers: %w[bar baz]],
              streams: [{ context: 'FooCtx', stream_name: 'Foo' }],
            },
          }
        end

        it 'construct proper collection' do
          stream_filter = PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo')
          marker_filter1 = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(
            event_type: 'Bar', markers: %w[foo bar]
          )
          marker_filter2 = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: %w[bar baz])
          event_type_filters = [
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Foo'),
          ]
          marker_rows = [
            PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(stream_filter:, marker_filter: marker_filter1),
            PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(stream_filter:, marker_filter: marker_filter2),
          ]
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            stream_filter:,
            event_type_filters: event_type_filters
          )
          expect(subject.collection).to eq([filter_row, *marker_rows])
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
              PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Foo'),
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
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Foo'),
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Bar'),
          ]
        )
        expect(subject.collection).to eq([filter_row])
      end
    end

    context 'when "prefix" event types filter is provided' do
      let(:options) { { filter: { event_types: ['Foo', { prefix: 'Bar' }] } } }

      it 'recognizes it' do
        filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          event_type_filters: [
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, event_type: 'Bar'),
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Foo'),
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
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Foo'),
          ]
        )
        expect(subject.collection).to eq([filter_row])
      end
    end

    context 'when one of event type filter provided as a hash' do
      let(:options) { { filter: { event_types: [{ type: 'Foo' }] } } }

      it 'recognizes it' do
        filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          event_type_filters: [
            PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Foo'),
          ]
        )
        expect(subject.collection).to eq([filter_row])
      end
    end

    context 'when incorrect event types filter is provided' do
      let(:options) { { filter: { event_types: {} } } }

      it_behaves_like 'empty collection'
    end

    context 'when event type with marker filter is provided' do
      context 'when markers array is not empty' do
        let(:options) { { filter: { event_types: [{ type: 'Foo', markers: %w[foo bar] }] } } }

        it 'recognizes it' do
          marker_filter = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(
            event_type: 'Foo', markers: %w[foo bar]
          )
          marker_filter_row = PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(marker_filter:)
          expect(subject.collection).to eq([marker_filter_row])
        end
      end

      context 'when markers array is empty' do
        let(:options) { { filter: { event_types: [{ type: 'Foo', markers: [] }] } } }

        it 'recognizes it as a regular event type filter' do
          event_type_filter = PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(
            event_type: 'Foo', prefix: false
          )
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            event_type_filters: [event_type_filter]
          )
          expect(subject.collection).to eq([filter_row])
        end
      end
    end

    context 'when markers filter is provided' do
      let(:options) { { filter: { event_types: [{ markers: %w[foo bar] }] } } }

      it 'recognizes it' do
        marker_filter = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: %w[foo bar])
        marker_filter_row = PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(marker_filter:)
        expect(subject.collection).to eq([marker_filter_row])
      end
    end

    context 'when incorrect event type with markers filter is provided' do
      context 'when :markers partially consists from strings' do
        let(:options) { { filter: { event_types: [{ type: 'Foo', markers: ['foo', :bar] }] } } }

        it 'recognizes string values only' do
          marker_filter = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(
            event_type: 'Foo', markers: %w[foo]
          )
          marker_filter_row = PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(marker_filter:)
          expect(subject.collection).to eq([marker_filter_row])
        end
      end

      context 'when :markers consists of non-string objects' do
        let(:options) { { filter: { event_types: [{ type: 'Foo', markers: %i[foo bar] }] } } }

        it_behaves_like 'empty collection'
      end
    end

    context 'when incorrect markers filter is provided' do
      context 'when :markers is empty' do
        let(:options) { { filter: { event_types: [{ markers: [] }] } } }

        it_behaves_like 'empty collection'
      end

      context 'when :markers consists of non-string objects' do
        let(:options) { { filter: { event_types: [{ markers: %i[foo bar] }] } } }

        it_behaves_like 'empty collection'
      end
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
              { context: 'FooCtx', stream_name: 'Foo' },
              { context: 'BarCtx', stream_name: 'Bar', stream_id: '1' },
            ],
            event_types: ['Foo', { prefix: 'Bar' }, { type: 'Baz', markers: %w[foo bar] }, { markers: %w[bar baz] }],
          },
        }
      end

      it 'recognizes them' do
        stream_filter1 = PgEventstore::QueryBuilders::Filters::StreamFilter.new(
          context: 'FooCtx', stream_name: 'Foo'
        )
        stream_filter2 = PgEventstore::QueryBuilders::Filters::StreamFilter.new(
          context: 'BarCtx', stream_name: 'Bar', stream_id: '1'
        )
        marker_filter1 = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(
          event_type: 'Baz', markers: %w[foo bar]
        )
        marker_filter2 = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: %w[bar baz])
        marker_rows = [
          PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(
            stream_filter: stream_filter1, marker_filter: marker_filter1
          ),
          PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(
            stream_filter: stream_filter2, marker_filter: marker_filter1
          ),
          PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(
            stream_filter: stream_filter1, marker_filter: marker_filter2
          ),
          PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(
            stream_filter: stream_filter2, marker_filter: marker_filter2
          ),
        ]
        event_type_filters = [
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, event_type: 'Bar'),
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Foo'),
        ]
        filter_row1 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: stream_filter1,
          event_type_filters: event_type_filters
        )
        filter_row2 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: stream_filter2,
          event_type_filters: event_type_filters
        )
        expect(subject.collection).to match_array([filter_row1, filter_row2, *marker_rows])
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
      let(:event_type_filter1) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Foo')
      end
      let(:event_type_filter2) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, event_type: 'Bar')
      end
      let(:marker_filter1) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Baz')
      end
      let(:marker_filter2) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: %w[foo bar])
      end
      let(:stream_filter1) do
        PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx')
      end
      let(:stream_filter2) do
        PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'BarCtx')
      end

      before do
        instance.add_event_type(event_type_filter1)
        instance.add_event_type(event_type_filter2)
        instance.add_marker(marker_filter1)
        instance.add_marker(marker_filter2)
        instance.add_stream(stream_filter1)
        instance.add_stream(stream_filter2)
      end

      it 'returns FilterRow-s - combinations of streams, event types filters and markers filters' do
        event_type_filters = [event_type_filter2, event_type_filter1]
        marker_rows = [
          PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(
            stream_filter: stream_filter1, marker_filter: marker_filter1
          ),
          PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(
            stream_filter: stream_filter2, marker_filter: marker_filter1
          ),
          PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(
            stream_filter: stream_filter1, marker_filter: marker_filter2
          ),
          PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(
            stream_filter: stream_filter2, marker_filter: marker_filter2
          ),
        ]
        filter_row1 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: stream_filter1,
          event_type_filters: event_type_filters
        )
        filter_row2 = PgEventstore::QueryBuilders::Filters::FilterRow.new(
          stream_filter: stream_filter2,
          event_type_filters: event_type_filters
        )
        is_expected.to match_array([filter_row1, filter_row2, *marker_rows])
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

      context 'when filters overlap by event types' do
        let(:event_type_filter1) do
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Bar')
        end
        let(:event_type_filter2) do
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, event_type: 'Bar')
        end
        let(:event_type_filter3) do
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, event_type: 'Ba')
        end

        before do
          instance.add_event_type(event_type_filter1)
          instance.add_event_type(event_type_filter2)
          instance.add_event_type(event_type_filter3)
        end

        it 'keeps more general one' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            event_type_filters: [event_type_filter3]
          )
          is_expected.to eq([filter_row])
        end
      end

      context 'when same event type appears in both - general and markers constraints' do
        let(:event_type_filter) do
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Bar')
        end
        let(:marker_filter) do
          PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Bar')
        end

        before do
          instance.add_marker(marker_filter)
          instance.add_event_type(event_type_filter)
        end

        it 'keeps more general one' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            event_type_filters: [event_type_filter]
          )
          is_expected.to eq([filter_row])
        end
      end

      context 'when same event type appears in both - prefix and markers constraints' do
        let(:event_type_filter) do
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, event_type: 'Ba')
        end
        let(:marker_filter) do
          PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Bar')
        end

        before do
          instance.add_marker(marker_filter)
          instance.add_event_type(event_type_filter)
        end

        it 'keeps more general one' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            event_type_filters: [event_type_filter]
          )
          is_expected.to eq([filter_row])
        end
      end

      context 'when same event type appears across all event type filter variants' do
        let(:event_type_filter1) do
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, event_type: 'Ba')
        end
        let(:event_type_filter2) do
          PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, event_type: 'Bar')
        end
        let(:marker_filter) do
          PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Bar')
        end

        before do
          instance.add_marker(marker_filter)
          instance.add_event_type(event_type_filter1)
          instance.add_event_type(event_type_filter2)
        end

        it 'keeps more general one' do
          filter_row = PgEventstore::QueryBuilders::Filters::FilterRow.new(
            event_type_filters: [event_type_filter1]
          )
          is_expected.to eq([filter_row])
        end
      end

      context 'when similar event type with markers filters are provided' do
        before do
          instance.add_marker(
            PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: %w[foo baz], event_type: 'Bar')
          )
          instance.add_marker(
            PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: %w[bar baz], event_type: 'Bar')
          )
        end

        it 'merges them into the single one' do
          marker_filter = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(
            event_type: 'Bar', markers: %w[foo baz bar]
          )
          filter_row = PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(marker_filter:)
          is_expected.to eq([filter_row])
        end
      end

      context 'when multiple markers filters are provided' do
        before do
          instance.add_marker(
            PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: %w[foo baz])
          )
          instance.add_marker(
            PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: %w[bar baz])
          )
        end

        it 'merges them into the single one' do
          marker_filter = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: %w[foo baz bar])
          filter_row = PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(marker_filter:)
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

    context 'when stream filter is context filter' do
      it 'marks instance as the one having an incomplete stream filter' do
        expect { subject }.to change { instance.has_incomplete_stream_filter? }.to(true)
      end
    end

    context 'when stream filter is stream name filter' do
      let(:stream_filter) do
        PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo')
      end

      it 'marks instance as the one having an incomplete stream filter' do
        expect { subject }.to change { instance.has_incomplete_stream_filter? }.to(true)
      end
    end

    context 'when stream filter is stream filter' do
      let(:stream_filter) do
        PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
      end

      it 'does not mark instance as having an incomplete stream filter' do
        expect { subject }.not_to change { instance.has_incomplete_stream_filter? }
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

    let(:event_type_filter) do
      PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(event_type: 'Foo', prefix: false)
    end
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
      it 'marks instance as the one having event types' do
        expect { subject }.to change { instance.has_event_types? }.to(true)
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

  describe '#add_marker' do
    subject { instance.add_marker(marker_filter) }

    let(:marker_filter) do
      PgEventstore::QueryBuilders::Filters::MarkerFilter.new(event_type: 'Foo', markers: ['foo'])
    end
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
        instance.add_marker(marker_filter)
      end

      it 'does not add another one' do
        expect { subject }.not_to change { instance.collection }
      end
    end

    context 'when the given filter is not added yet' do
      it 'adds it' do
        filter_row = PgEventstore::QueryBuilders::Filters::MarkerFilterRow.new(marker_filter:)
        expect { subject }.to change { instance.collection }.to([filter_row])
      end
      it 'marks instance as the one having markers' do
        expect { subject }.to change { instance.has_markers? }.to(true)
      end

      context 'when filter is a markers filter' do
        let(:marker_filter) do
          PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'])
        end

        it 'marks instance as the one having an incomplete markers filter' do
          expect { subject }.to change { instance.has_incomplete_markers_filter? }.to(true)
        end
      end

      context 'when filter is event type with marker filter' do
        it 'does not change mark an instance as having an incomplete markers filter' do
          expect { subject }.not_to change { instance.has_incomplete_markers_filter? }
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

    context 'when collection contains event type with marker filters' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Bar')
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains markers filter' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'])
      end

      before do
        instance.add_marker(marker_filter)
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

    context 'when collection contains event type with marker filters' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Bar')
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains markers filter' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'])
      end

      before do
        instance.add_marker(marker_filter)
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

    context 'when collection contains event type with marker filters' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Bar')
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains markers filter' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'])
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(false) }
    end

    describe 'when collection is empty' do
      it { is_expected.to eq(false) }
    end
  end

  describe '#has_markers?' do
    subject { instance.has_markers? }

    let(:instance) { described_class.new }

    context 'when collection contains event type filters' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: false)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains prefix filters' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: true)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains stream filters' do
      let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

      before do
        instance.add_stream(stream_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains event type with marker filters' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Bar')
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(true) }
    end

    context 'when collection contains markers filter' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'])
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(true) }
    end

    describe 'when collection is empty' do
      it { is_expected.to eq(false) }
    end
  end

  describe '#has_incomplete_markers_filter?' do
    subject { instance.has_incomplete_markers_filter? }

    let(:instance) { described_class.new }

    context 'when collection contains event type filters' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: false)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains prefix filters' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: true)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains stream filters' do
      let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

      before do
        instance.add_stream(stream_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains event type with marker filters' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Bar')
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains markers filter' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'])
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(true) }
    end

    describe 'when collection is empty' do
      it { is_expected.to eq(false) }
    end
  end

  describe '#has_incomplete_stream_filter?' do
    subject { instance.has_incomplete_stream_filter? }

    let(:instance) { described_class.new }

    context 'when collection contains event type filters' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: false)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains prefix filters' do
      let(:event_type_filter) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(value: 'Foo', prefix: true)
      end

      before do
        instance.add_event_type(event_type_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains stream filters' do
      let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

      before do
        instance.add_stream(stream_filter)
      end

      context 'when stream filter is a context filter' do
        it { is_expected.to eq(true) }
      end

      context 'when stream filter is a stream name filter' do
        let(:stream_filter) do
          PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo')
        end

        it { is_expected.to eq(true) }
      end

      context 'when stream filter is a stream filter' do
        let(:stream_filter) do
          PgEventstore::QueryBuilders::Filters::StreamFilter.new(
            context: 'FooCtx', stream_name: 'Foo', stream_id: '1'
          )
        end

        it { is_expected.to eq(false) }
      end
    end

    context 'when collection contains event type with marker filters' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type: 'Bar')
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(false) }
    end

    context 'when collection contains markers filter' do
      let(:marker_filter) do
        PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'])
      end

      before do
        instance.add_marker(marker_filter)
      end

      it { is_expected.to eq(false) }
    end

    describe 'when collection is empty' do
      it { is_expected.to eq(false) }
    end
  end
end

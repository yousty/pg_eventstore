# frozen_string_literal: true

RSpec.describe PgEventstore::QueryBuilders::Filters::FilterRow do
  describe '.null_filter_row' do
    subject { described_class.null_filter_row }

    it 'returns filter row without stream filter and with the only null event type filter' do
      is_expected.to(
        eq(
          described_class.new(event_type_filters: [PgEventstore::QueryBuilders::Filters::EventTypeFilter.null_filter])
        )
      )
    end
  end

  describe '#flatten' do
    subject { instance.flatten }

    context 'when event type filters are present' do
      let(:instance) do
        described_class.new(stream_filter:, event_type_filters: [event_type_filter1, event_type_filter2])
      end

      let(:event_type_filter1) do
        PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo')
      end
      let(:event_type_filter2) { PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: true, value: 'Bar') }
      let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

      it 'expands each event type filter into a separate FilterRow' do
        is_expected.to(
          eq(
            [
              described_class.new(stream_filter:, event_type_filters: [event_type_filter1]),
              described_class.new(stream_filter:, event_type_filters: [event_type_filter2]),
            ]
          )
        )
      end
    end

    context 'when event type filters are empty' do
      let(:instance) { described_class.new(stream_filter:, event_type_filters: []) }
      let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

      it 'returns new FilterRow with same attributes as source' do
        aggregate_failures do
          is_expected.to(
            eq(
              [
                described_class.new(stream_filter: stream_filter, event_type_filters: []),
              ]
            )
          )
          expect(subject.__id__).not_to eq(instance.__id__)
        end
      end
    end
  end

  describe '#collapsable_into_event_types_only?' do
    subject { instance.collapsable_into_event_types_only? }

    let(:instance) do
      described_class.new(stream_filter:, event_type_filters:)
    end
    let(:stream_filter) { nil }
    let(:event_type_filters) { [] }

    context 'when stream filter is present' do
      context 'when stream filter is a context filter' do
        let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

        context 'when event type filters are empty' do
          it { is_expected.to eq(false) }
        end

        context 'when event type filters are present' do
          let(:event_type_filters) do
            [PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(event_type: 'Foo', prefix: false)]
          end

          it { is_expected.to eq(true) }
        end
      end

      context 'when stream filter is a stream name filter' do
        let(:stream_filter) do
          PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo')
        end

        context 'when event type filters are empty' do
          it { is_expected.to eq(false) }
        end

        context 'when event type filters are present' do
          let(:event_type_filters) do
            [PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(event_type: 'Foo', prefix: false)]
          end

          it { is_expected.to eq(true) }
        end
      end

      context 'when stream filter is a stream filter' do
        let(:stream_filter) do
          PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
        end

        context 'when event type filters are empty' do
          it { is_expected.to eq(false) }
        end

        context 'when event type filters are present' do
          let(:event_type_filters) do
            [PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(event_type: 'Foo', prefix: false)]
          end

          it { is_expected.to eq(false) }
        end
      end
    end

    context 'when stream filter is absent' do
      context 'when event type filters are empty' do
        it { is_expected.to eq(false) }
      end

      context 'when event type filters are present' do
        let(:event_type_filters) do
          [PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(event_type: 'Foo', prefix: false)]
        end

        it { is_expected.to eq(true) }
      end
    end
  end

  describe '#ambiguous_event_type?' do
    subject { instance.ambiguous_event_type? }

    let(:instance) do
      described_class.new(stream_filter:, event_type_filters:)
    end
    let(:stream_filter) { nil }
    let(:event_type_filters) { [] }

    context 'when some event type filter is a prefix filter' do
      let(:event_type_filters) do
        [PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(event_type: 'Foo', prefix: true)]
      end

      it { is_expected.to eq(true) }
    end

    context 'when event type filters are absent' do
      it { is_expected.to eq(false) }
    end

    context 'when event type filters are present' do
      let(:event_type_filters) do
        [PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(event_type: 'Foo', prefix: false)]
      end

      context 'when stream filter is absent' do
        it { is_expected.to eq(true) }
      end

      context 'when stream filter is a context filter' do
        let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

        it { is_expected.to eq(true) }
      end

      context 'when stream filter is a stream name filter' do
        let(:stream_filter) do
          PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo')
        end

        it { is_expected.to eq(false) }
      end

      context 'when stream filter is a stream filter' do
        let(:stream_filter) do
          PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
        end

        it { is_expected.to eq(false) }
      end
    end
  end
end

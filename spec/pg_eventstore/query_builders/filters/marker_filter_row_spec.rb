# frozen_string_literal: true

RSpec.describe PgEventstore::QueryBuilders::Filters::MarkerFilterRow do
  describe '#flatten' do
    subject { instance.flatten }

    let(:instance) do
      described_class.new(stream_filter:, marker_filter:)
    end
    let(:stream_filter) do
      PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
    end
    let(:markers) { ['foo'] }
    let(:marker_filter) { PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers:, event_type: 'Foo') }

    context 'when number of markers is 1' do
      it { is_expected.to eq([instance]) }
    end

    context 'when number of markers is more than 1' do
      let(:markers) { %w[foo bar] }

      it 'returns marker filter row per marker' do
        marker_filter1 = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(event_type: 'Foo', markers: ['foo'])
        marker_filter2 = PgEventstore::QueryBuilders::Filters::MarkerFilter.new(event_type: 'Foo', markers: ['bar'])
        is_expected.to(
          eq(
            [
              described_class.new(stream_filter:, marker_filter: marker_filter1),
              described_class.new(stream_filter:, marker_filter: marker_filter2),
            ]
          )
        )
      end
    end
  end

  describe '#ambiguous_event_type?' do
    subject { instance.ambiguous_event_type? }

    let(:instance) do
      described_class.new(stream_filter:, marker_filter:)
    end
    let(:stream_filter) { nil }
    let(:event_type) { nil }
    let(:marker_filter) { PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type:) }

    context 'when event type is absent' do
      context 'when stream filter is absent' do
        it { is_expected.to eq(false) }
      end

      context 'when stream filter is present' do
        context 'when stream filter is context' do
          let(:stream_filter) { PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx') }

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
    end

    context 'when event type is present' do
      let(:event_type) { 'Foo' }

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

  describe '#to_filter_row' do
    subject { instance.to_filter_row }

    let(:instance) do
      described_class.new(stream_filter:, marker_filter:)
    end
    let(:stream_filter) do
      PgEventstore::QueryBuilders::Filters::StreamFilter.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
    end
    let(:event_type) { nil }
    let(:marker_filter) { PgEventstore::QueryBuilders::Filters::MarkerFilter.new(markers: ['foo'], event_type:) }

    context 'when event type is absent' do
      it 'create FilterRow without event types' do
        is_expected.to eq(PgEventstore::QueryBuilders::Filters::FilterRow.new(stream_filter:, event_type_filters: []))
      end
    end

    context 'when event type is present' do
      let(:event_type) { 'Foo' }

      it 'create FilterRow with event types' do
        event_type_filter = PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(event_type:, prefix: false)
        is_expected.to(
          eq(
            PgEventstore::QueryBuilders::Filters::FilterRow.new(
              stream_filter:,
              event_type_filters: [event_type_filter]
            )
          )
        )
      end
    end
  end
end

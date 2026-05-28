# frozen_string_literal: true

RSpec.describe PgEventstore::QueryBuilders::Filters::FilterRow do
  describe '#flatten' do
    subject { instance.flatten }

    context 'when event type filters are present' do
      let(:instance) do
        described_class.new(stream_filter:, event_type_filters: [event_type_filter1, event_type_filter2])
      end

      let(:event_type_filter1) { PgEventstore::QueryBuilders::Filters::EventTypeFilter.new(prefix: false, value: 'Foo') }
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
end

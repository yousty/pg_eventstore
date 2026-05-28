# frozen_string_literal: true

RSpec.describe PgEventstore::QueryBuilders::Filters::EventTypeFilter do
  describe '.null_filter' do
    subject { described_class.null_filter }

    it 'returns null filter' do
      aggregate_failures do
        is_expected.to be_a(described_class)
        expect(subject.value).to eq(nil)
        expect(subject.prefix).to eq(false)
      end
    end
  end

  describe '#prefix?' do
    subject { instance.prefix? }

    let(:instance) { described_class.new(value: 'Foo', prefix:) }
    let(:prefix) { false }

    context 'when filter is a prefix' do
      let(:prefix) { true }

      it { is_expected.to eq(true) }
    end

    context 'when filter is a regular filter' do
      it { is_expected.to eq(false) }
    end
  end

  describe '#to_sql_value' do
    subject { instance.to_sql_value }

    let(:instance) { described_class.new(value: 'Foo', prefix:) }
    let(:prefix) { false }

    context 'when filter is a prefix' do
      let(:prefix) { true }

      it { is_expected.to eq('Foo%') }
    end

    context 'when filter is a regular filter' do
      it { is_expected.to eq('Foo') }
    end
  end
end

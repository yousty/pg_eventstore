# frozen_string_literal: true

RSpec.describe PgEventstore::QueryBuilders::ReadCursor::StreamCursor do
  describe '.from_options' do
    subject { described_class.from_options(options) }

    let(:options) { { from_position: 1, to_position: 2, direction: 'asc', max_count: 3 } }

    it 'creates "all" stream cursor' do
      aggregate_failures do
        is_expected.to be_all_stream_cursor
        expect(subject.from).to eq(1)
        expect(subject.to).to eq(2)
        expect(subject.direction).to eq('asc')
        expect(subject.max_count).to eq(3)
      end
    end
  end

  describe '.from_stream_and_options' do
    subject { described_class.from_stream_and_options(stream, options) }

    let(:stream) { PgEventstore::Stream.all_stream }
    let(:options) { {} }

    context 'when stream is "all" stream' do
      let(:options) { { from_position: 1, to_position: 2, direction: 'asc', max_count: 3 } }

      it 'creates "all" stream cursor' do
        aggregate_failures do
          is_expected.to be_all_stream_cursor
          expect(subject.from).to eq(1)
          expect(subject.to).to eq(2)
          expect(subject.direction).to eq('asc')
          expect(subject.max_count).to eq(3)
        end
      end
    end

    context 'when stream is a regular stream' do
      let(:options) { { from_revision: 1, to_revision: 2, direction: 'asc', max_count: 3 } }
      let(:stream) { PgEventstore::Stream.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

      it 'creates regular stream cursor' do
        aggregate_failures do
          is_expected.not_to be_all_stream_cursor
          expect(subject.from).to eq(1)
          expect(subject.to).to eq(2)
          expect(subject.direction).to eq('asc')
          expect(subject.max_count).to eq(3)
        end
      end
    end
  end

  describe '#from' do
    subject { instance.from }

    let(:instance) { described_class.new(cursor) }
    let(:cursor) { described_class::AllStreamCursor.new(from_position: 1) }

    context 'when cursor is "all" stream cursor' do
      it 'returns its from_position' do
        is_expected.to eq(1)
      end
    end

    context 'when cursor is regular stream cursor' do
      let(:cursor) { described_class::RegularStreamCursor.new(from_revision: 1) }

      it 'returns its from_revision' do
        is_expected.to eq(1)
      end
    end
  end

  describe '#to' do
    subject { instance.to }

    let(:instance) { described_class.new(cursor) }
    let(:cursor) { described_class::AllStreamCursor.new(to_position: 1) }

    context 'when cursor is "all" stream cursor' do
      it 'returns its to_position' do
        is_expected.to eq(1)
      end
    end

    context 'when cursor is regular stream cursor' do
      let(:cursor) { described_class::RegularStreamCursor.new(to_revision: 1) }

      it 'returns its to_revision' do
        is_expected.to eq(1)
      end
    end
  end

  describe '#direction' do
    subject { instance.direction }

    let(:instance) { described_class.new(cursor) }
    let(:cursor) { described_class::AllStreamCursor.new(direction: :asc) }

    context 'when cursor is "all" stream cursor' do
      it 'returns its :direction' do
        is_expected.to eq(:asc)
      end
    end

    context 'when cursor is regular stream cursor' do
      let(:cursor) { described_class::RegularStreamCursor.new(direction: :asc) }

      it 'returns its :direction' do
        is_expected.to eq(:asc)
      end
    end
  end

  describe '#max_count' do
    subject { instance.max_count }

    let(:instance) { described_class.new(cursor) }
    let(:cursor) { described_class::AllStreamCursor.new(max_count: 1) }

    context 'when cursor is "all" stream cursor' do
      it 'returns its :max_count' do
        is_expected.to eq(1)
      end
    end

    context 'when cursor is regular stream cursor' do
      let(:cursor) { described_class::RegularStreamCursor.new(max_count: 1) }

      it 'returns its :max_count' do
        is_expected.to eq(1)
      end
    end
  end

  describe '#max_count=' do
    subject { instance.max_count = 2 }

    let(:instance) { described_class.new(cursor) }
    let(:cursor) { described_class::AllStreamCursor.new(max_count: 1) }

    context 'when cursor is "all" stream cursor' do
      it 'changes max count' do
        expect { subject }.to change { instance.max_count }.to(2)
      end
    end

    context 'when cursor is regular stream cursor' do
      let(:cursor) { described_class::RegularStreamCursor.new(max_count: 1) }

      it 'changes max count' do
        expect { subject }.to change { instance.max_count }.to(2)
      end
    end
  end

  describe '#all_stream_cursor?' do
    subject { instance.all_stream_cursor? }

    let(:instance) { described_class.new(cursor) }
    let(:cursor) { described_class::AllStreamCursor.new }

    context 'when cursor is "all" stream cursor' do
      it { is_expected.to eq(true) }
    end

    context 'when cursor is regular stream cursor' do
      let(:cursor) { described_class::RegularStreamCursor.new }

      it { is_expected.to eq(false) }
    end
  end
end

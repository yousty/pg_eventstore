# frozen_string_literal: true

RSpec.describe PgEventstore::QueryBuilders::Filters::StreamFilter do
  describe '#context?' do
    subject { instance.context? }

    let(:instance) { described_class.new(context: 'FooCtx') }

    context 'when filter is a context filter' do
      it { is_expected.to eq(true) }
    end

    context 'when filter is a stream name filter' do
      let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo') }

      it { is_expected.to eq(false) }
    end

    context 'when filter is a stream filter' do
      let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

      it { is_expected.to eq(false) }
    end
  end

  describe '#stream_name?' do
    subject { instance.stream_name? }

    let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo') }

    context 'when filter is a context filter' do
      let(:instance) { described_class.new(context: 'FooCtx') }

      it { is_expected.to eq(false) }
    end

    context 'when filter is a stream name filter' do
      it { is_expected.to eq(true) }
    end

    context 'when filter is a stream filter' do
      let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

      it { is_expected.to eq(false) }
    end
  end

  describe '#stream?' do
    subject { instance.stream? }

    let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

    context 'when filter is a context filter' do
      let(:instance) { described_class.new(context: 'FooCtx') }

      it { is_expected.to eq(false) }
    end

    context 'when filter is a stream name filter' do
      let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo') }

      it { is_expected.to eq(false) }
    end

    context 'when filter is a stream filter' do
      it { is_expected.to eq(true) }
    end
  end

  describe '#to_partition_h' do
    subject { instance.to_partition_h }

    context 'when filter is a context filter' do
      let(:instance) { described_class.new(context: 'FooCtx') }

      it 'returns its hash' do
        is_expected.to eq(context: 'FooCtx')
      end
    end

    context 'when filter is a stream name filter' do
      let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo') }

      it 'returns its hash' do
        is_expected.to eq(context: 'FooCtx', stream_name: 'Foo')
      end
    end

    context 'when filter is a stream filter' do
      let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

      it 'keeps partition-related attributes only' do
        is_expected.to eq(context: 'FooCtx', stream_name: 'Foo')
      end
    end
  end

  describe '#to_h' do
    subject { instance.to_h }

    context 'when filter is a context filter' do
      let(:instance) { described_class.new(context: 'FooCtx') }

      it 'returns its hash' do
        is_expected.to eq(context: 'FooCtx')
      end
    end

    context 'when filter is a stream name filter' do
      let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo') }

      it 'returns its hash' do
        is_expected.to eq(context: 'FooCtx', stream_name: 'Foo')
      end
    end

    context 'when filter is a stream filter' do
      let(:instance) { described_class.new(context: 'FooCtx', stream_name: 'Foo', stream_id: '1') }

      it 'returns its hash' do
        is_expected.to eq(context: 'FooCtx', stream_name: 'Foo', stream_id: '1')
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe PgEventstore::Stream do
  let(:instance) { described_class.new(context: 'SomeContext', stream_name: 'SomeStreamName', stream_id: '123') }

  describe 'constants' do
    describe 'BIGINT' do
      subject { described_class::BIGINT }

      it 'has correct range' do
        is_expected.to eq(-9223372036854775808..9223372036854775807)
      end
      it 'does not exceed 8 bytes limit' do
        expect((-subject.begin + subject.end).to_s(16)).to eq('ffffffffffffffff')
      end
    end
  end

  describe '.all_stream' do
    subject { described_class.all_stream }

    it 'defines special object' do
      aggregate_failures do
        expect(subject.instance_variable_get(:@all_stream)).to eq(true)
        expect(subject.instance_variables).to eq([:@all_stream])
      end
    end
  end

  describe '#all_stream?' do
    subject { instance.all_stream? }

    context 'when stream is a regular stream' do
      it { is_expected.to eq(false) }
    end

    context 'when stream is "all" stream' do
      let(:instance) { described_class.all_stream }

      it { is_expected.to eq(true) }
    end
  end

  describe '#deconstruct' do
    subject { instance.deconstruct }

    it 'returns attributes values in an array' do
      is_expected.to eq(%w[SomeContext SomeStreamName 123])
    end
  end

  describe '#deconstruct_keys' do
    subject { instance.deconstruct_keys(keys) }

    let(:keys) { %i[context stream_id] }

    context 'when keys to deconstruct are present' do
      it 'returns a hash, which includes only those keys' do
        is_expected.to eq(context: 'SomeContext', stream_id: '123')
      end
    end

    context 'when keys do not correspond the attributes' do
      let(:keys) { %i[some-key] }

      it { is_expected.to eq({}) }
    end

    context 'when keys is nil' do
      let(:keys) { nil }

      it 'returns a hash with all attributes and their values' do
        is_expected.to eq(context: 'SomeContext', stream_name: 'SomeStreamName', stream_id: '123')
      end
    end
  end

  describe '#to_hash' do
    subject { instance.to_hash }

    it 'returns a hash with all attributes and their values' do
      is_expected.to eq(context: 'SomeContext', stream_name: 'SomeStreamName', stream_id: '123')
    end
  end

  describe '#==' do
    subject { instance == another_instance }

    let(:another_instance) do
      described_class.new(context: 'SomeContext', stream_name: 'SomeStreamName', stream_id: '123')
    end

    context 'when all attributes match' do
      it { is_expected.to eq(true) }
    end

    context 'when some attribute differs' do
      let(:another_instance) do
        described_class.new(context: 'SomeContext', stream_name: 'SomeStreamName', stream_id: '321')
      end

      it { is_expected.to eq(false) }
    end

    context 'when another instance is not a Stream object' do
      let(:another_instance) { Object.new }

      it { is_expected.to eq(false) }
    end
  end

  describe '#lock_id' do
    subject { instance.lock_id }

    it 'calculates bigint representation of the stream, based on its attributes' do
      is_expected.to eq(-4582894943774205551)
    end
  end
end

# frozen_string_literal: true

RSpec.describe PgEventstore::Utils do
  describe '.underscore_str' do
    subject { described_class.underscore_str(str) }

    let(:str) { 'SomeName' }

    it { is_expected.to eq('some_name') }

    context 'when string is already underscored' do
      let(:str) { 'some_name' }

      it 'returns it as is' do
        is_expected.to eq('some_name')
      end
    end
  end

  describe '.benchmark' do
    subject { described_class.benchmark { sleep 1.1 } }

    it 'returns time the given block took to execute' do
      is_expected.to be_between(1.1, 1.2)
    end
  end

  describe '.range_to_slice' do
    subject(:range_to_slice) { described_class.range_to_slice(partition_ids, max_partitions_per_call) }

    let(:partition_ids) { [] }
    let(:max_partitions_per_call) { 2 }

    context 'when index count is within the max partition count' do
      let(:partition_ids) { [1, 2] }

      it { is_expected.to eq(0..) }
    end

    context 'when unique partition count exceeds the max partition count' do
      let(:partition_ids) { [1, 2, 3, 3] }

      it { is_expected.to eq(0..1) }
    end

    context 'when index count exceeds the max but unique partition count does not' do
      let(:partition_ids) { [1, 2, 1, 2] }

      it { is_expected.to eq(0..) }
    end
  end
end

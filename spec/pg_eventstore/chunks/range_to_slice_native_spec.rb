# frozen_string_literal: true

RSpec.describe 'native range_to_slice' do
  shared_examples 'native range_to_slice implementation' do |chunk_class|
    subject(:range_to_slice) { chunk.send(:range_to_slice, partition_ids, max_partitions_per_call) }

    let(:chunk) { chunk_class.allocate }
    let(:partition_ids) { [] }
    let(:max_partitions_per_call) { 2 }

    before do
      stub_const("#{chunk_class}::MAX_PARTITIONS_TO_RESOLVE_PER_CALL", max_partitions_per_call)
    end

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

  it_behaves_like 'native range_to_slice implementation',
                  PgEventstore::Chunks::ReadApiEventsIndexChunk

  it_behaves_like 'native range_to_slice implementation',
                  PgEventstore::Chunks::SubscriptionEventsIndexChunk
end

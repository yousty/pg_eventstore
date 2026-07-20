# frozen_string_literal: true

RSpec.describe PgEventstore::Chunks::ReplicaEventsIndexChunk do
  let(:instance) { described_class.new(indexes) }
  let(:indexes) { [index1, index2, index3] }
  let(:index1) do
    PgEventstore::EventGlobalIndex::SubscriptionRepr.new(
      global_position: 1, subscription_position: 1, event_type_partition_id: 1
    )
  end
  let(:index2) do
    PgEventstore::EventGlobalIndex::SubscriptionRepr.new(
      global_position: 2, subscription_position: 2, event_type_partition_id: 1
    )
  end
  let(:index3) do
    PgEventstore::EventGlobalIndex::SubscriptionRepr.new(
      global_position: 3, subscription_position: 3, event_type_partition_id: 1
    )
  end

  describe '#take' do
    subject { instance.take(size) }

    let(:size) { 2 }

    context 'when chunk is not drained' do
      it 'drains up to the given amount of events' do
        expect { subject }.to change { instance.instance_variable_get(:@indexes) }.to([index3])
      end
      it 'changes chunks size' do
        expect { subject }.to change { instance.size }.by(-size)
      end
      it 'returns drained events' do
        is_expected.to eq([index1, index2])
      end
    end

    context 'when chunk is drained' do
      before do
        instance.take(indexes.size)
      end

      it { is_expected.to eq([]) }
    end
  end

  describe '#drained?' do
    subject { instance.drained? }

    context 'when chunk is not drained' do
      it { is_expected.to eq(false) }
    end

    context 'when chunk is drained' do
      before do
        instance.take(indexes.size)
      end

      it { is_expected.to eq(true) }
    end
  end

  describe '#size' do
    subject { instance.size }

    it 'returns the number of events in the chunk' do
      is_expected.to eq(indexes.size)
    end
  end

  describe '#last' do
    subject { instance.last }

    context 'when chunk is not drained' do
      it 'returns last event in the chunk' do
        is_expected.to eq(index3)
      end
    end

    context 'when chunk is drained' do
      before do
        instance.take(indexes.size)
      end

      it { is_expected.to eq(nil) }
    end
  end
end

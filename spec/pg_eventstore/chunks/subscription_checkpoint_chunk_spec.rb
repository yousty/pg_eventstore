# frozen_string_literal: true

RSpec.describe PgEventstore::Chunks::SubscriptionCheckpointChunk do
  let(:instance) { described_class.new(position) }
  let(:position) { 123 }

  describe '#take' do
    subject { instance.take(1) }

    context 'when chunk is not drained' do
      it { is_expected.to eq([described_class::Checkpoint.new(subscription_position: position)]) }
    end

    context 'when chunk is drained' do
      before do
        instance.take(1)
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
        instance.take(1)
      end

      it { is_expected.to eq(true) }
    end
  end

  describe '#size' do
    subject { instance.size }

    context 'when chunk is not drained' do
      it { is_expected.to eq(1) }
    end

    context 'when chunk is drained' do
      before do
        instance.take(1)
      end

      it { is_expected.to eq(0) }
    end
  end

  describe '#last' do
    subject { instance.last }

    context 'when chunk is not drained' do
      it { is_expected.to eq(described_class::Checkpoint.new(subscription_position: position)) }
    end

    context 'when chunk is drained' do
      before do
        instance.take(1)
      end

      it { is_expected.to eq(nil) }
    end
  end
end

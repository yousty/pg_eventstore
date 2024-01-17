# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionHandlerPerformance do
  let(:instance) { described_class.new }

  describe '#track_exec_time' do
    subject { instance.track_exec_time { :foo } }

    it 'yields the given block' do
      expect { |b| instance.track_exec_time(&b) }.to yield_with_no_args
    end
    it 'returns the result of the block' do
      is_expected.to eq(:foo)
    end
  end

  describe '#average_event_time' do
    subject { instance.average_event_time }

    context 'when there were no measurement yet' do
      it { is_expected.to be_zero }
    end

    context 'when there are some measurement already' do
      before do
        stub_const("#{described_class}::TIMINGS_TO_KEEP", 2)
        instance.track_exec_time { sleep 0.1 }
        instance.track_exec_time { sleep 0.2 }
        instance.track_exec_time { sleep 0.3 }
      end

      it 'returns average value of last TIMINGS_TO_KEEP measurements' do
        expect(subject.round(3)).to eq(0.25)
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe PgEventstore::SubscriptionHandlerPerformance do
  let(:instance) { described_class.new }

  describe '#track_exec_time' do
    subject { instance.track_exec_time(events_number) { :foo } }

    let(:events_number) { 2 }

    it 'yields the given block' do
      expect { |b| instance.track_exec_time(events_number, &b) }.to yield_with_no_args
    end
    it 'returns the result of the block' do
      is_expected.to eq(:foo)
    end
  end

  describe '#average_event_processing_time' do
    subject { instance.average_event_processing_time }

    context 'when there were no measurement yet' do
      it { is_expected.to be_zero }
    end

    context 'when there are some measurement already' do
      let(:events_number) { 2 }

      let(:sleep1) { 0.1 }
      let(:sleep2) { 0.2 }
      let(:sleep3) { 0.3 }

      before do
        stub_const("#{described_class}::TIMINGS_TO_KEEP", 2)
        instance.track_exec_time(events_number) { sleep sleep1 }
        instance.track_exec_time(events_number) { sleep sleep2 }
        instance.track_exec_time(events_number) { sleep sleep3 }
      end

      it 'returns average value of last TIMINGS_TO_KEEP measurements' do
        expected_time = (sleep2 + sleep3) / events_number / described_class::TIMINGS_TO_KEEP
        expect(subject.round(2)).to eq(expected_time.round(2))
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe PgEventstore::RunnerState do
  let(:instance) { described_class.new }

  it { is_expected.to be_a(PgEventstore::Extensions::CallbacksExtension) }

  shared_examples 'state transition' do
    context 'when object is in the given state' do
      before do
        instance.public_send("#{state}!")
      end

      it { is_expected.to be_truthy }
    end

    context 'when object is in another state' do
      before do
        another_state = state == :dead ? :stopped : :dead
        instance.public_send("#{another_state}!")
      end

      it { is_expected.to eq(false) }
    end
  end

  shared_examples 'sets the state' do
    let(:on_state_changed_cbx) { proc { |state| state_changed_receiver.call(state) } }
    let(:state_changed_receiver) { double('State changed receiver') }

    context 'when current state differs from new' do
      before do
        instance.define_callback(:change_state, :after, on_state_changed_cbx)
        allow(state_changed_receiver).to receive(:call)
      end

      it 'changes the state' do
        expect { subject }.to change { instance.to_s }.to(state)
      end
      it 'runs :change_state action' do
        subject
        expect(state_changed_receiver).to have_received(:call).with(state)
      end
    end

    context 'when the instance is already in the given state' do
      before do
        instance.public_send("#{state}!")
        instance.define_callback(:change_state, :after, on_state_changed_cbx)
        allow(state_changed_receiver).to receive(:call)
      end

      it 'does not run :change_state action' do
        subject
        expect(state_changed_receiver).not_to have_received(:call)
      end
    end
  end

  describe 'constants' do
    describe 'STATES' do
      subject { described_class::STATES }

      it { expect(subject.keys).to eq(%i(initial running halting stopped dead)) }
      it { expect(subject.values).to eq(%w(initial running halting stopped dead)) }
      it { expect(subject.values).to all be_frozen }
      it { is_expected.to be_frozen }
    end
  end

  describe '#initial?' do
    subject { instance.initial? }

    it_behaves_like 'state transition' do
      let(:state) { :initial }
    end

    it 'is in the :initial state by default' do
      is_expected.to be_truthy
    end
  end

  describe '#running?' do
    subject { instance.running? }

    it_behaves_like 'state transition' do
      let(:state) { :running }
    end
  end

  describe '#halting?' do
    subject { instance.halting? }

    it_behaves_like 'state transition' do
      let(:state) { :halting }
    end
  end

  describe '#stopped?' do
    subject { instance.stopped? }

    it_behaves_like 'state transition' do
      let(:state) { :stopped }
    end
  end

  describe '#dead?' do
    subject { instance.dead? }

    it_behaves_like 'state transition' do
      let(:state) { :dead }
    end
  end

  describe '#initial!' do
    subject { instance.initial! }

    before do
      instance.dead!
    end

    it_behaves_like 'sets the state' do
      let(:state) { 'initial' }
    end
  end

  describe '#running!' do
    subject { instance.running! }

    it_behaves_like 'sets the state' do
      let(:state) { 'running' }
    end
  end

  describe '#halting!' do
    subject { instance.halting! }

    it_behaves_like 'sets the state' do
      let(:state) { 'halting' }
    end
  end

  describe '#stopped!' do
    subject { instance.stopped! }

    it_behaves_like 'sets the state' do
      let(:state) { 'stopped' }
    end
  end

  describe '#dead!' do
    subject { instance.dead! }

    it_behaves_like 'sets the state' do
      let(:state) { 'dead' }
    end
  end

  describe '#to_s' do
    subject { instance.to_s }

    it 'returns string representation of current state' do
      is_expected.to eq('initial')
    end
  end
end

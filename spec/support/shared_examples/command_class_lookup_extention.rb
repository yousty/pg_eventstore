# frozen_string_literal: true

RSpec.shared_examples 'Command class lookup extension' do
  describe '.command_class' do
    subject { described_class.command_class(cmd_name) }

    let(:cmd_name) { 'Stop' }

    context 'when command is recognizable' do
      it 'returns its class' do
        is_expected.to eq(described_class::Stop)
      end
    end

    context 'when command is not recognizable' do
      let(:cmd_name) { 'Foo' }

      it 'returns Base class' do
        is_expected.to eq(described_class::Base)
      end
    end
  end
end

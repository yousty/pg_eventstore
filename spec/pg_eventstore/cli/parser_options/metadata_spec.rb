# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::ParserOptions::Metadata do
  let(:instance) { described_class.new }

  describe 'instance' do
    subject { instance }

    it { is_expected.to be_a(PgEventstore::Extensions::OptionsExtension) }
    it { is_expected.to have_option(:short) }
    it { is_expected.to have_option(:long) }
    it { is_expected.to have_option(:description) }
  end

  describe '#to_parser_opts' do
    subject { instance.to_parser_opts }

    let(:instance) { described_class.new(short: '-l', long: '--line', description: 'A line opt') }

    it { is_expected.to eq(['-l', '--line', 'A line opt']) }
  end

  describe '#hash' do
    let(:hash) { {} }
    let(:metadata1) { described_class.new(short: '-l', long: '--line', description: 'A line opt') }
    let(:metadata2) { described_class.new(short: '-l', long: '--line', description: 'A line opt') }

    before do
      hash[metadata1] = :foo
    end

    context 'when metadata matches' do
      it 'recognizes second metadata' do
        expect(hash[metadata2]).to eq(:foo)
      end
    end

    context 'when metadata do not match' do
      let(:metadata2) { described_class.new(short: '-s', long: '--side', description: 'A side opt') }

      it 'does not recognize second metadata' do
        expect(hash[metadata2]).to eq(nil)
      end
    end
  end

  describe '#==' do
    subject { instance == another_instance }

    let(:instance) { described_class.new(short: '-l', long: '--line', description: 'A line opt') }
    let(:another_instance) { described_class.new(short: '-l', long: '--line', description: 'A line opt') }

    context 'when all attributes match' do
      it { is_expected.to eq(true) }
    end

    context 'when some attribute differs' do
      let(:another_instance) { described_class.new(short: '-l', long: '--line', description: 'A line option') }

      it { is_expected.to eq(false) }
    end

    context 'when another instance is not a Metadata object' do
      let(:another_instance) { Object.new }

      it { is_expected.to eq(false) }
    end
  end
end

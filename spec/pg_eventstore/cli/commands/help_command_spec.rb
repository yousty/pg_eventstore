# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::Commands::HelpCommand do
  let(:instance) { described_class.new(options) }
  let(:options) { PgEventstore::CLI::ParserOptions::BaseOptions.new }

  describe '#call' do
    subject { instance.call }

    before do
      options.help = 'This is a help message'
    end

    it 'prints help' do
      expect { subject }.to output(a_string_including('This is a help message')).to_stdout
    end
    it { is_expected.to eq(PgEventstore::CLI::ExitCodes::SUCCESS) }
  end
end

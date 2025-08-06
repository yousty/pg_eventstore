# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::Parsers::BaseParser do
  let(:dummy_parser) do
    Class.new(described_class) do
      def self.banner
        'Hi there!'
      end
    end
  end
  let(:instance) { dummy_parser.new(args, options) }
  let(:args) { [] }
  let(:options) { PgEventstore::CLI::ParserOptions::BaseOptions.new }

  describe '#parse' do
    subject { instance.parse }

    let(:args) { %w[command1 command2 -h] }

    it 'returns a list of commands and parsed options' do
      is_expected.to eq([%w[command1 command2], options])
    end
    it 'parses options' do
      expect { subject }.to change { options.help }.to(a_string_including(dummy_parser.banner))
    end
  end
end

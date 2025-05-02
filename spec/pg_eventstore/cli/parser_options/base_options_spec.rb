# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::ParserOptions::BaseOptions do
  let(:instance) { described_class.new }

  describe 'instance' do
    subject { instance }

    it 'has :help option' do
      metadata = PgEventstore::CLI::ParserOptions::Metadata.new(
        short: '-h', long: '--help', description: 'Prints this help'
      )
      is_expected.to have_option(:help).with_metadata(metadata)
    end
    it 'has :requires option' do
      metadata = PgEventstore::CLI::ParserOptions::Metadata.new(
        short: '-rFILE_PATH',
        long: '--require=FILE_PATH',
        description: 'Ruby files to load. You can provide this option multiple times to load more files.'
      )
      is_expected.to have_option(:requires).with_metadata(metadata).with_default_value([])
    end
    it { is_expected.to be_a(PgEventstore::Extensions::OptionsExtension) }
  end

  describe '#attach_parser_handlers' do
    subject { instance.attach_parser_handlers(parser) }

    let(:parser) { OptionParser.new }

    before do
      # We don't want to suddenly exit during test run. Ruby >= 3.4.0 and ruby < 3.4.0 handle exit differently. Thus,
      # we need to stub it differently.
      if RUBY_VERSION >= Gem::Version.new('3.4.0')
        allow(parser).to receive(:exit)
        allow(parser).to receive(:puts)
      else
        allow(OptionParser).to receive(:exit)
        allow(OptionParser).to receive(:puts)
      end
    end

    it 'registers "-h" option' do
      expect { subject }.to change { parser.parse(['-h']); instance.help }.to(a_string_including('Prints this help'))
    end
    it 'registers "-r" option' do
      expect { subject }.to change {
        begin
          parser.parse(['-r1.rb'])
        rescue OptionParser::InvalidOption
        end
        instance.requires
      }.to(['1.rb'])
    end
  end

  describe '#to_parser_opts' do
    subject { instance.to_parser_opts(option) }

    let(:option) { :help }

    it 'returns an array of arguments for OptionParser#on' do
      is_expected.to eq(['-h', '--help', 'Prints this help'])
    end
  end

  describe '#option' do
    subject { instance.option(option) }

    let(:option) { :help }

    it 'gets Option instance by the given symbol' do
      is_expected.to eq(PgEventstore::Extensions::OptionsExtension::Option.new(option))
    end
  end
end

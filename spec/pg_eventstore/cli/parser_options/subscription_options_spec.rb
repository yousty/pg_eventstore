# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::ParserOptions::SubscriptionOptions do
  let(:instance) { described_class.new }

  describe 'instance' do
    subject { instance }

    it { is_expected.to be_a(PgEventstore::CLI::ParserOptions::BaseOptions) }
    it 'has :pid_path option' do
      metadata = PgEventstore::CLI::ParserOptions::Metadata.new(
        short: '-pFILE_PATH',
        long: '--pid=FILE_PATH',
        description: 'Defines pid file path. Defaults to /tmp/pg-es_subscriptions.pid'
      )
      is_expected.to have_option(:pid_path).with_default_value('/tmp/pg-es_subscriptions.pid').with_metadata(metadata)
    end
  end

  describe '#attach_parser_handlers' do
    subject { instance.attach_parser_handlers(parser) }

    let(:parser) { OptionParser.new }

    before do
      allow(OptionParser).to receive(:exit)
      allow(OptionParser).to receive(:puts)
    end

    it 'registers "-p" option' do
      expect { subject }.to change {
        begin
          parser.parse(['-pmy.pid'])
        rescue OptionParser::InvalidOption
        end
        instance.pid_path
      }.to('my.pid')
    end
  end
end

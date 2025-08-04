# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::Parsers::DefaultParser do
  subject { instance }

  let(:instance) { described_class.new(args, options) }
  let(:args) { [] }
  let(:options) { PgEventstore::CLI::ParserOptions::BaseOptions.new }

  it { is_expected.to be_a(PgEventstore::CLI::Parsers::BaseParser) }

  describe '.banners' do
    subject { described_class.banner }

    it { is_expected.to match(a_string_including('Usage: pg-eventstore [options]')) }
  end
end

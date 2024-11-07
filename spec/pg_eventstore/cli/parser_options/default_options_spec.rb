# frozen_string_literal: true

RSpec.describe PgEventstore::CLI::ParserOptions::DefaultOptions do
  it { is_expected.to be_a(PgEventstore::CLI::ParserOptions::BaseOptions) }
end

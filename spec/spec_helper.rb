# frozen_string_literal: true

require 'pg_eventstore'
require 'pg_eventstore/rspec/has_option_matcher'
require 'securerandom'
require 'redis'

Dir[File.join(File.expand_path('.', __dir__), 'support/**/*.rb')].each { |f| require f }

REDIS = Redis.new(host: 'localhost', port: '6579')

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = "log/rspec_status.log"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended, and will default to
    # `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end

  # Many RSpec users commonly either run the entire suite or an individual
  # file, and it's useful to allow more verbose output when running an
  # individual spec file.
  if config.files_to_run.one?
    # Use the documentation formatter for detailed output,
    # unless a formatter has already been configured
    # (e.g. via a command-line flag).
    config.default_formatter = "doc"
  end

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = :random

  # Seed global randomization in this process using the `--seed` CLI option.
  # Setting this allows you to use `--seed` to deterministically reproduce
  # test failures related to randomization by passing the same `--seed` value
  # as the one that triggered the failure.
  Kernel.srand config.seed

  config.before do
    REDIS.flushdb
    # Some tests reset default config, connection, etc. Thus. reconfigure a client before each test
    PgEventstore.configure do |config|
      config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI') { 'postgresql://postgres:postgres@localhost:5532/eventstore_test' }
      config.connection_pool_size = 20
    end
    # Clean up db
    PgEventstore.connection.with { |c| c.exec('TRUNCATE events') }
  end

  config.include EventHelpers
end

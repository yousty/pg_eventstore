# PgEventstore

Implements database and API to store and read events in event sourced systems.

## Requirements

- `pg_eventstore` requires a PostgreSQL v16+ with [pg_cron](https://github.com/citusdata/pg_cron) extension installed.
- `pg_evenstore` requires a separate detabase. However, it is recommended that you spin it up on a separate PostgreSQL instance in a production environment.
- `pg_eventstore` requires `default_transaction_isolation` server config option to be set to `'read committed'` (default behavior). Having this value set to move strict isolation level may result in unexpected behavior.
- It is recommended to use a connection pooler (for example [PgBouncer](https://www.pgbouncer.org/)) in `transaction` pool mode to lower the load on a database.
- `pg_eventstore` requires ruby v3+. The development of this gem is targeted at [current](https://endoflife.date/ruby) ruby versions.

## Installation

Install the gem and add to the application's Gemfile by executing:
```bash
bundle add pg_eventstore
```

If bundler is not being used to manage dependencies, install the gem by executing:
```bash
gem install pg_eventstore
```

## Usage

Before start using the gem - you have to create the database. **It is important you to create and migrate via provided commands - they also include an important setup of `pg_cron` jobs as well. Even if you would like to restore your db backup on clean PostgreSQL instance - please initialize pg_eventstore via built-in tools first.** Please include this line into your `Rakefile`:

```ruby
load 'pg_eventstore/tasks/setup.rake'
```

This will include necessary rake tasks. You can now run 
```bash
# Replace this with your real connection url
export PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/eventstore"
bundle exec rake pg_eventstore:create
bundle exec rake pg_eventstore:migrate
```

to create the database, necessary database objects and migrate them to the latest version. After this step your `pg_eventstore` is ready to use. There is also a `rake pg_eventstore:drop` task which drops the database.

Documentation chapters:

- [Configuration](docs/configuration.md)
- [Events and streams definitions](docs/events_and_streams.md)
- [Appending events](docs/appending_events.md)
- [Linking events](docs/linking_events.md)
- [Reading events](docs/reading_events.md)
- [Subscriptions](docs/subscriptions.md)
- [Maintenance functions](docs/maintenance.md)
- [Writing middlewares](docs/writing_middleware.md)
- [How to make multiple commands atomic](docs/multiple_commands.md)
- [Admin UI](docs/admin_ui.md)

## CLI

The gem is shipped with its own CLI. Use `pg-eventstore --help` to find out its capabilities.

## Maintenance

You may want to backup your eventstore database. It is important to mention that you don't want to dump/restore records of `events_horizon` table. `events_horizon` table is used to supply subscriptions functionality and contains temporary data which is scoped to the PostgreSQL cluster they were created in. **Thus, it is even may be harmful if you restore records from this table into a new PostgreSQL cluster. Simply exclude that table's data when performing backups.** Example:

```bash
pg_dump --exclude-table-data=events_horizon eventstore -U postgres > eventstore.sql
```

## RSpec

### Clean up test db

The gem provides a class to clean up your `pg_eventstore` test db between tests. Example usage(in your `spec/spec_helper.rb`:

```ruby
require 'pg_eventstore/rspec/test_helpers'

RSpec.configure do |config|
  config.before do
    PgEventstore::TestHelpers.clean_up_db
  end
end
```

### RSpec matcher for OptionsExtension

If you would like to be able to test the functional, provided by `PgEventstore::Extensions::OptionsExtension` extension - there is a rspec matcher. Load custom matcher in you `spec_helper.rb`:

```ruby
require 'pg_eventstore/rspec/has_option_matcher'
```

Let's say you have next class:
```ruby
class SomeClass
  include PgEventstore::Extensions::OptionsExtension

  option(:some_opt, metadata: { foo: :bar }) { '1' }
end
```

To test that its instance has the proper option with the proper default value and proper metadata you can use this matcher:
```ruby
RSpec.describe SomeClass do
  subject { described_class.new }

  # Check that :some_opt is present
  it { is_expected.to have_option(:some_opt) }
  # Check that :some_opt is present and has the correct default value
  it { is_expected.to have_option(:some_opt).with_default_value('1').with_metadata(foo: :bar) }
end
```

## Development

After checking out the repo, run:
- `bundle` to install dependencies
- `docker compose up` to start dev/test services
- `bin/setup_db` to create/re-create development and test databases, tables and related objects
- `bundle exec rbs collection install` to install external rbs definitions

Then, run `bin/rspec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

To run admin UI web server - run `puma` in your terminal. By default it will start web server on `http://0.0.0.0:9292`.

### Benchmarks

There is a script to help you to tests the `pg_eventstore` implementation performance. You can run it using next command:

```bash
./benchmark/run
```

### Publishing new version

1. Push commit with updated `version.rb` file to the `release` branch. The new version will be automatically pushed to [rubygems](https://rubygems.org).
2. Create release on GitHub.
3. Update `CHANGELOG.md`

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yousty/pg_eventstore. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/yousty/pg_eventstore/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the PgEventstore project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/yousty/pg_eventstore/blob/master/CODE_OF_CONDUCT.md).

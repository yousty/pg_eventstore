# PgEventstore

Implements database and API to store and read events in event sourced systems.

## Requirements

`pg_eventstore` requires a PostgreSQL database with jsonb data type support (which means you need to have v9.2+). However it is recommended to use a non [EOL](https://www.postgresql.org/support/versioning/) PostgreSQL version, because the development of this gem is targeted at current PostgreSQL versions.
`pg_eventstore` requires ruby v3+. The development of this gem is targeted at [current](https://endoflife.date/ruby) ruby versions.

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add pg_eventstore

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install pg_eventstore

## Usage

Before you start, make sure you created a database where events will be stored. A PostgreSQL user must be a superuser to be able to create tables, indexes, primary/foreign keys, etc. Please don't use an existing database/user for this purpose. Example of creating such database and user:

```bash
sudo -u postgres createuser pg_eventstore --superuser
sudo -u postgres psql --command="CREATE DATABASE eventstore OWNER pg_eventstore"
sudo -u postgres psql --command="CREATE DATABASE eventstore OWNER pg_eventstore"
```

If necessary - adjust your `pg_hba.conf` to allow `pg_eventstore` user to connect to your PostgreSQL server. 

Next step will be configuring a db connection. Please check the **Configuration** chapter bellow to find out how to do it.

After db connection is configured - it is time to create necessary database objects. Please include this line into your `Rakefile`:

```ruby
load "pg_eventstore/tasks/setup.rake"
```

This will include necessary rake tasks. You can now run 
```bash
bundle exec rake pg_eventstore:create
```
to create necessary database objects. After this step your `pg_eventstore` is ready to use.

Documentation chapters:

- [Configuration](docs/configuration.md)
- [Events and streams definitions](docs/events_and_streams.md)
- [Appending events](docs/appending_events.md)
- [Reading events](docs/reading_events.md)
- [Writing middlewares](docs/writing_middleware.md)
- [How to make multiple commands atomic](docs/multiple_commands.md)

## Development

After checking out the repo, run:
- `bundle` to install dependencies
- `docker-compose up` to start dev/test services
- `bin/setup_db` to create/re-create development and test databases, tables and related objects 

Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

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

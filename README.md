# PgEventstore

Implements database and API to store and read events in event sourced systems.

## Requirements

- `pg_eventstore` requires a PostgreSQL database with jsonb data type support (which means you need to have v9.2+). However it is recommended to use a non [EOL](https://www.postgresql.org/support/versioning/) PostgreSQL version, because the development of this gem is targeted at current PostgreSQL versions. 
- It is recommend you to have the default value set for `default_transaction_isolation` PostgreSQL config setting(`"read committed"`) as the implementation relies on it. All other transaction isolation levels(`"repeatable read"` and `"serializable"`) may cause unexpected serialization errors which you will have to handle by yourself(e.g. by always wrapping your code using [`#multiple`](docs/multiple_commands.md)).
- `pg_eventstore` requires ruby v3+. The development of this gem is targeted at [current](https://endoflife.date/ruby) ruby versions.

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add pg_eventstore

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install pg_eventstore

## Usage

Before start using the gem - you have to create the database. Please include this line into your `Rakefile`:

```ruby
load "pg_eventstore/tasks/setup.rake"
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
- [Writing middlewares](docs/writing_middleware.md)
- [How to make multiple commands atomic](docs/multiple_commands.md)

## Admin web UI

`pg_eventstore` implements admin UI where you can browse various database objects. It is implemented as rack application. It doesn't have any authentication/authorization mechanism - it is your responsibility to take care of it.

### Rails integration

In your `config/routes.rb`:

```ruby
require 'pg_eventstore/web'

mount PgEventstore::Web::Application, at: '/eventstore'
```

### Standalone application

Create `config.ru` file and place next content in there:

```ruby
require 'pg_eventstore/web'

run PgEventstore::Web::Application
```

Now you can use any web server to run it.

## Development

After checking out the repo, run:
- `bundle` to install dependencies
- `docker-compose up` to start dev/test services
- `bin/setup_db` to create/re-create development and test databases, tables and related objects 

Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

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

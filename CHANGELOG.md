## [Unreleased]

## [0.9.0] - 2024-02-23

- Use POSIX locale for streams and event types

## [0.8.0] - 2024-02-20

- Allow float values for `subscription_pull_interval`. The default value of it was also set to `1.0`(it was `2` previously)

## [0.7.2] - 2024-02-14

- Fix the implementation for PostgreSQL v11

## [0.7.1] - 2024-02-09

- Fix rake tasks

## [0.7.0] - 2024-02-09

- Refactor `pg_eventstore:create` and `pg_eventstore:drop` rake tasks. They now actually create/drop the database. You will have to execute `delete from migrations where number > 6` query before deploying this version.
- Drop legacy migrations

## [0.6.0] - 2024-02-08

- Add stream info into `PgEventstore::WrongExpectedRevisionError` error details

## [0.5.3] - 2024-02-07

- Fix `pg_eventstore:drop` rake task

## [0.5.2] - 2024-02-06

- Improve speed of `PgEventstore::Stream#eql?` a bit

## [0.5.1] - 2024-02-06

- Fix `PgEventstore::Stream` to be properly recognizable inside Hash

## [0.5.0] - 2024-02-05

- Fix event class resolving when providing `resolve_link_tos: true` option
- Return correct stream revision of the `Event#stream` object of the appended event
- Implement events linking feature
- Implement paginated read
- Remove duplicated `idx_events_event_type_id` index

## [0.4.0] - 2024-01-29

- Implement asynchronous subscriptions. Refer to the documentation for more info

## [0.3.0] - 2024-01-24

- Log SQL queries when `PgEvenstore.logger` is set and it is in `:debug` mode 

## [0.2.6] - 2023-12-20

- Remove `events.type` column

## [0.2.5] - 2023-12-20

- Fix bug when migrations files are returned in unsorted order on some systems

## [0.2.4] - 2023-12-20

Due to performance issues under certain circumstances, searching by event type was giving bad performance. I decided to extract `type` column from `events` table into separated table. **No breaking changes in public API though.**

**Warning** The migrations this version has, requires you to shut down applications that use `pg_eventstore` and only then run `rake pg_eventstore:migrate`.

## [0.2.3] - 2023-12-18

- Fix performance when searching by event type only(under certain circumstances PosetgreSQL was picking wrong index).

## [0.2.2] - 2023-12-14

- Fix `pg_eventstore:drop` rake task to also drop `migrations` table

## [0.2.1] - 2023-12-14

Under certain circumstances `PG::TRSerializationFailure` exception wasn't retried. Adjust connection's states list to fix that.

## [0.2.0] - 2023-12-14

- Improve performance by reviewing indexes
- Implement migrations

Please run `rake pg_eventstore:migrate` to migrate eventstore db to actual version.

## [0.1.0] - 2023-12-12

Initial release.

- Implement Read command
- Implement AppendToStream command
- Implement Multiple command

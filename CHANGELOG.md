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

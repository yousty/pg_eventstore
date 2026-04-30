#!/usr/bin/env sh

# Create separate, clean database to further dump its structure without potential app-specific partitions that could
# be present in regular pg_eventstore database
PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/es_migrations" bundle exec rake pg_eventstore:drop
PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/es_migrations" bundle exec rake pg_eventstore:create
PG_EVENTSTORE_URI="postgresql://postgres:postgres@localhost:5532/es_migrations" bundle exec rake pg_eventstore:migrate

docker compose exec -it postgres pg_dump -U postgres -d es_migrations --schema-only --no-privileges --no-owner > db/structure.sql

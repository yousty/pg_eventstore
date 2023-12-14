#!/usr/bin/env sh

docker compose exec -it postgres pg_dump -U postgres -d eventstore --schema-only --no-privileges --no-owner > db/structure.sql

# frozen_string_literal: true

require 'pg_eventstore/web'

PgEventstore.configure do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI', 'postgresql://postgres:postgres@localhost:5532/eventstore')
  config.connection_pool_size = 5
end

PgEventstore.configure(name: :with_middlewares) do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI', 'postgresql://postgres:postgres@localhost:5532/eventstore')
  config.connection_pool_size = 5
  config.middlewares = { event_trace: PgEventstore::Middleware::EventTracing.new }
end

PgEventstore.configure(name: :eventstore_test) do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI', 'postgresql://postgres:postgres@localhost:5532/eventstore_test')
  config.connection_pool_size = 3
end

PgEventstore.configure(name: :with_middlewares_test) do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI', 'postgresql://postgres:postgres@localhost:5532/eventstore_test')
  config.connection_pool_size = 3
  config.middlewares = { event_trace: PgEventstore::Middleware::EventTracing.new }
end

run PgEventstore::Web::Application

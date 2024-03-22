# frozen_string_literal: true

require 'pg_eventstore/web'

PgEventstore.configure do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI') { 'postgresql://postgres:postgres@localhost:5532/eventstore' }
  config.connection_pool_size = 5
end

PgEventstore.configure(name: :eventstore_test) do |config|
  config.pg_uri = ENV.fetch('PG_EVENTSTORE_URI') { 'postgresql://postgres:postgres@localhost:5532/eventstore_test' }
  config.connection_pool_size = 3
end

run PgEventstore::Web::Application

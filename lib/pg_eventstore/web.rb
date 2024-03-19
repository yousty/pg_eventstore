# frozen_string_literal: true

require 'sinatra/base'
require 'pg_eventstore/web/paginator/helpers'
require 'pg_eventstore/web/paginator/base_collection'
require 'pg_eventstore/web/paginator/events_collection'
require 'pg_eventstore/web/paginator/stream_contexts_collection'
require 'pg_eventstore/web/paginator/stream_names_collection'
require 'pg_eventstore/web/paginator/stream_ids_collection'
require 'pg_eventstore/web/paginator/event_types_collection'
require 'pg_eventstore/web/application'

module PgEventstore
  module Web
  end
end

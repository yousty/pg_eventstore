# frozen_string_literal: true

require 'pg_eventstore'
require 'sinatra/base'
require_relative 'web/paginator/helpers'
require_relative 'web/paginator/base_collection'
require_relative 'web/paginator/events_collection'
require_relative 'web/paginator/stream_contexts_collection'
require_relative 'web/paginator/stream_names_collection'
require_relative 'web/paginator/stream_ids_collection'
require_relative 'web/paginator/event_types_collection'
require_relative 'web/subscriptions/set_collection'
require_relative 'web/subscriptions/subscriptions'
require_relative 'web/subscriptions/subscriptions_set'
require_relative 'web/subscriptions/subscriptions_to_set_association'
require_relative 'web/subscriptions/with_state/set_collection'
require_relative 'web/subscriptions/with_state/subscriptions'
require_relative 'web/subscriptions/with_state/subscriptions_set'
require_relative 'web/subscriptions/helpers'
require_relative 'web/application'

module PgEventstore
  module Web
  end
end

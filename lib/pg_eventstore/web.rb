# frozen_string_literal: true

require 'pg_eventstore'
require 'sinatra/base'
require_relative 'web/paginator/helpers'
require_relative 'web/paginator/base_collection'
require_relative 'web/paginator/events_collection'
require_relative 'web/paginator/streams_collection'
require_relative 'web/paginator/stream_contexts_collection'
require_relative 'web/paginator/stream_names_collection'
require_relative 'web/paginator/stream_ids_collection'
require_relative 'web/paginator/event_types_collection'
require_relative 'web/paginator/markers_collection'
require_relative 'web/subscriptions/set_collection'
require_relative 'web/subscriptions/subscriptions'
require_relative 'web/subscriptions/subscriptions_set'
require_relative 'web/subscriptions/subscriptions_to_set_association'
require_relative 'web/subscriptions/with_state/set_collection'
require_relative 'web/subscriptions/with_state/subscriptions'
require_relative 'web/subscriptions/with_state/subscriptions_set'
require_relative 'web/subscriptions/helpers'
require_relative 'web/metrics/metric_family'
require_relative 'web/metrics/formatter'
require_relative 'web/metrics/collectors/base'
require_relative 'web/metrics/collectors/subscriptions_latency'
require_relative 'web/metrics/collectors/subscriptions_health'
require_relative 'web/metrics/collectors/subscriptions_throughput'
require_relative 'web/metrics/helpers'
require_relative 'web/metrics/application'
require_relative 'web/application'

module PgEventstore
  module Web
  end
end

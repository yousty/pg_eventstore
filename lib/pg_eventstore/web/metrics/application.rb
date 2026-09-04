# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      # Standalone rack application serving subscription metrics in the Prometheus text exposition format.
      #
      # It ships without any authentication - how the endpoint is protected is up to the application mounting it,
      # the same way it is for the Admin UI (see docs/admin_ui.md#authorization).
      #
      # Which pg_eventstore database is queried is chosen per request with the "config" query param, so one mounted
      # app can serve metrics of every configured store:
      #
      #   GET /subscriptions/latency?config=db1
      #
      # An absent config means the default one; an unknown config is answered with 404 rather than silently served from
      # the default store, so a misconfigured scrape shows up as a failing target instead of as wrong data. Add "set"
      # params to report only some subscription sets - repeat the param for several: "?set=SetA&set=SetB".
      class Application < Sinatra::Base
        set :environment, -> { (ENV['RACK_ENV'] || ENV['RAILS_ENV'] || ENV['APP_ENV'])&.to_sym || :development }
        set :logging, false
        set :sessions, false
        set :host_authorization, { allow_if: ->(_env) { true } }

        helpers(Helpers) do
          # @return [PgEventstore::Connection]
          def metrics_connection
            PgEventstore.connection(config_name)
          end

          # Name of the config to query: the "config" param when given, the default config otherwise. Halts with 404
          # for a name that is not configured.
          # @return [Symbol]
          def config_name
            requested = params[:config].to_s
            return PgEventstore::DEFAULT_CONFIG if requested.empty?
            return requested.to_sym if PgEventstore.available_configs.include?(requested.to_sym)

            halt 404, { 'content-type' => 'text/plain' }, "Unknown config #{requested.inspect}"
          end
        end

        get('/subscriptions') do
          metrics_response(
            [Collectors::SubscriptionsLatency, Collectors::SubscriptionsHealth, Collectors::SubscriptionsThroughput]
          )
        end

        # The only route querying event positions - one index range scan per subscription.
        get('/subscriptions/latency') do
          metrics_response([Collectors::SubscriptionsLatency])
        end

        get('/subscriptions/health') do
          metrics_response([Collectors::SubscriptionsHealth])
        end

        get('/subscriptions/throughput') do
          metrics_response([Collectors::SubscriptionsThroughput])
        end
      end
    end
  end
end

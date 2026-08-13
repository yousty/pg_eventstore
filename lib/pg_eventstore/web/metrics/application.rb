# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      # Standalone rack application serving Prometheus metrics. Unlike the admin UI - which is expected to sit
      # behind a human-oriented authentication - this app is meant to be scraped by Prometheus, so it supports
      # static bearer token authentication out of the box: set the PG_EVENTSTORE_METRICS_TOKEN environment
      # variable and every request must carry an "Authorization: Bearer <token>" header. When the variable is not
      # set, the app is open - protecting it is then your responsibility.
      #
      # Uses the :metrics config when defined, with a fallback to the default config.
      class Application < Sinatra::Base
        # @return [Symbol]
        DEFAULT_METRICS_CONFIG = :metrics
        # @return [String]
        AUTH_TOKEN_ENV_VAR = 'PG_EVENTSTORE_METRICS_TOKEN'

        set :environment, -> { (ENV['RACK_ENV'] || ENV['RAILS_ENV'] || ENV['APP_ENV'])&.to_sym || :development }
        set :logging, false
        set :sessions, false
        set :host_authorization, { allow_if: ->(_env) { true } }

        helpers(Helpers) do
          # @return [PgEventstore::Connection]
          def metrics_connection
            PgEventstore.connection(config_name)
          end

          # @return [Symbol]
          def config_name
            return DEFAULT_METRICS_CONFIG if PgEventstore.available_configs.include?(DEFAULT_METRICS_CONFIG)

            PgEventstore::DEFAULT_CONFIG
          end

          # @return [void]
          def authorize!
            token = ENV[AUTH_TOKEN_ENV_VAR].to_s
            return if token.empty?

            provided = request.env['HTTP_AUTHORIZATION'].to_s.delete_prefix('Bearer ')
            halt 401, { 'content-type' => 'text/plain' }, 'Unauthorized' unless
              Rack::Utils.secure_compare(token, provided)
          end
        end

        before do
          authorize!
        end

        Routes.define(self)
      end
    end
  end
end

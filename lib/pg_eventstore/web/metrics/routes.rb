# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      # Defines the metrics routes on a Sinatra application. Used twice: with an empty prefix by the standalone
      # {Metrics::Application} and with the "/metrics" prefix by {Web::Application}, so both serve identical
      # payloads at their respective paths.
      module Routes
        # Per-path collector split. Each path runs only its own query, so scrape jobs can poll the cheap families
        # more often than the expensive ones (the latency query is the only one touching the events table).
        # @return [Hash<String => Array<Class<PgEventstore::Web::Metrics::Collectors::Base>>>]
        COLLECTORS_BY_PATH = {
          '/subscriptions/latency' => [Collectors::SubscriptionsLatency],
          '/subscriptions/health' => [Collectors::SubscriptionsHealth],
          '/subscriptions/throughput' => [Collectors::SubscriptionsThroughput],
        }.freeze

        class << self
          # @param app [Class<Sinatra::Base>]
          # @param prefix [String] either "" or a "/"-prefixed path
          # @return [void]
          def define(app, prefix: '')
            all_collectors = COLLECTORS_BY_PATH.values.flatten.uniq
            app.get(prefix.empty? ? '/' : prefix) do
              metrics_response(all_collectors)
            end
            COLLECTORS_BY_PATH.each do |path, collectors|
              app.get("#{prefix}#{path}") do
                metrics_response(collectors)
              end
            end
          end
        end
      end
    end
  end
end

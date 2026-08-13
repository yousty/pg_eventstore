# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      # Defines the metrics routes on a Sinatra application. Used twice: with an empty prefix by the standalone
      # {Metrics::Application} and with the "/metrics" prefix by {Web::Application}, so both serve identical
      # payloads at their respective paths.
      module Routes
        # Collectors of each metrics domain, keyed by the domain's path. A domain also gets an aggregate route
        # serving all of its collectors at once - handy for ad-hoc inspection.
        #
        # There is deliberately NO route serving every domain: "/metrics" is the Prometheus convention, so a route
        # there would invite pointing scrape jobs at it by reflex, and every such scrape would pay for every query
        # - including the expensive ones. Splitting per path exists precisely so cheap families are not billed for
        # the costly ones, and each response stays bounded by its domain as more are added.
        # @return [Hash<String => Hash<String => Array<Class<PgEventstore::Web::Metrics::Collectors::Base>>>>]
        COLLECTORS_BY_DOMAIN = {
          '/subscriptions' => {
            # The only query touching the events table - one index hop per subscription.
            '/latency' => [Collectors::SubscriptionsLatency],
            '/health' => [Collectors::SubscriptionsHealth],
            '/throughput' => [Collectors::SubscriptionsThroughput],
          },
        }.freeze

        class << self
          # @param app [Class<Sinatra::Base>]
          # @param prefix [String] either "" or a "/"-prefixed path
          # @return [void]
          def define(app, prefix: '')
            COLLECTORS_BY_DOMAIN.each do |domain, collectors_by_path|
              define_domain_routes(app, prefix, domain, collectors_by_path)
            end
          end

          private

          # @param app [Class<Sinatra::Base>]
          # @param prefix [String]
          # @param domain [String]
          # @param collectors_by_path [Hash<String => Array<Class<PgEventstore::Web::Metrics::Collectors::Base>>>]
          # @return [void]
          def define_domain_routes(app, prefix, domain, collectors_by_path)
            domain_collectors = collectors_by_path.values.flatten.uniq
            app.get("#{prefix}#{domain}") do
              metrics_response(domain_collectors)
            end
            collectors_by_path.each do |path, collectors|
              app.get("#{prefix}#{domain}#{path}") do
                metrics_response(collectors)
              end
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      # Route helpers of {Metrics::Application}.
      module Helpers
        # @param collector_classes [Array<Class<PgEventstore::Web::Metrics::Collectors::Base>>]
        # @return [String]
        def metrics_response(collector_classes)
          connection = metrics_connection
          families = collector_classes.flat_map { _1.new(connection, sets: requested_sets).call }
          content_type(Formatter::CONTENT_TYPE)
          Formatter.new.call(families)
        end

        # Subscription sets a scrape asks for, given as one or more "set" query params. Empty means every set.
        # @return [Array<String>]
        def requested_sets
          Array(params[:set]).map(&:to_s).reject(&:empty?)
        end
      end
    end
  end
end

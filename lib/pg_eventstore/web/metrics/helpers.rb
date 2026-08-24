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

        # Subscription sets a scrape asks for. Accepts a repeated param ("?set=A&set=B" - what Prometheus emits for
        # `params: {set: [A, B]}`) or a comma separated list ("?set=A,B"). Empty means every set.
        #
        # The query string is parsed directly because Sinatra's `params` keeps only the last value of a repeated key
        # unless it is written as "set[]", which Prometheus does not do.
        # @return [Array<String>]
        def requested_sets
          query = Rack::Utils.parse_query(request.query_string)
          Array(query['set'] || query['set[]']).flat_map { _1.to_s.split(',') }.map(&:strip).reject(&:empty?)
        end
      end
    end
  end
end

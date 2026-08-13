# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      # Route helpers shared by {Metrics::Application} and the /metrics routes of {Web::Application}.
      module Helpers
        # @param collector_classes [Array<Class<PgEventstore::Web::Metrics::Collectors::Base>>]
        # @return [String]
        def metrics_response(collector_classes)
          families = collector_classes.flat_map { |collector_class| collector_class.new(metrics_connection).call }
          content_type(Formatter::CONTENT_TYPE)
          Formatter.new.call(families)
        end
      end
    end
  end
end

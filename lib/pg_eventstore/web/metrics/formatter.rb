# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      # Renders metric families into the Prometheus text exposition format (version 0.0.4).
      class Formatter
        # @return [String]
        CONTENT_TYPE = 'text/plain; version=0.0.4; charset=utf-8'

        # @param families [Array<PgEventstore::Web::Metrics::MetricFamily>]
        # @return [String]
        def call(families)
          "#{families.map { |family| format_family(family) }.join("\n")}\n"
        end

        private

        # @param family [PgEventstore::Web::Metrics::MetricFamily]
        # @return [String]
        def format_family(family)
          lines = ["# HELP #{family.name} #{family.help}", "# TYPE #{family.name} #{family.type}"]
          family.samples.each do |sample|
            lines.push("#{family.name}#{format_labels(sample[:labels])} #{sample[:value]}")
          end
          lines.join("\n")
        end

        # @param labels [Hash<Symbol => String>]
        # @return [String]
        def format_labels(labels)
          return '' if labels.empty?

          "{#{labels.map { |name, value| %(#{name}="#{escape_label_value(value.to_s)}") }.join(',')}}"
        end

        # @param value [String]
        # @return [String]
        def escape_label_value(value)
          value.gsub('\\', '\\\\\\\\').gsub("\n", '\\n').gsub('"', '\\"')
        end
      end
    end
  end
end

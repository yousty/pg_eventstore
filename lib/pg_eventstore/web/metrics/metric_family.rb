# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      # A collection of samples of a single Prometheus metric.
      class MetricFamily
        # @!attribute name
        #   @return [String]
        attr_reader :name
        # @!attribute type
        #   @return [String] "gauge" or "counter"
        attr_reader :type
        # @!attribute help
        #   @return [String]
        attr_reader :help
        # @!attribute samples
        #   @return [Array<Hash>]
        attr_reader :samples

        # @param name [String]
        # @param type [String]
        # @param help [String]
        def initialize(name:, type:, help:)
          @name = name
          @type = type
          @help = help
          @samples = []
        end

        # @param labels [Hash<Symbol => String>]
        # @param value [Integer, Float]
        # @return [void]
        def add_sample(labels:, value:)
          @samples.push({ labels:, value: })
        end
      end
    end
  end
end

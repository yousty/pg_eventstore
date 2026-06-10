# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      # @!visibility private
      class EventTypeFilter
        include Extensions::OptionsExtension
        include Extensions::OptionsDefaults

        class << self
          # @return [PgEventstore::QueryBuilders::Filters::EventTypeFilter]
          def null_filter
            new(value: nil, prefix: false)
          end
        end

        # @!attribute value
        #   @return [String, nil]
        attribute(:value)
        # @!attribute prefix
        #   @return [Boolean]
        attribute(:prefix)

        # @return [Boolean]
        def prefix?
          prefix
        end

        # @return [String, nil]
        def to_sql_value
          prefix? ? "#{value}%" : value
        end
      end
    end
  end
end

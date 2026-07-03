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
            new(event_type: nil, prefix: false)
          end
        end

        # @!attribute value
        #   @return [String, nil]
        attribute(:event_type)
        # @!attribute prefix
        #   @return [Boolean]
        attribute(:prefix)

        # @return [Boolean]
        def prefix?
          prefix
        end

        # @return [String, nil]
        def to_sql_value
          prefix? ? "#{event_type}%" : event_type
        end
      end
    end
  end
end

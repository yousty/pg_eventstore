# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      # @!visibility private
      class MarkerFilter
        include Extensions::OptionsExtension
        include Extensions::OptionsDefaults

        # @!attribute marker
        #   @return [Array<String>]
        attribute(:markers)
        # @!attribute event_type
        #   @return [String, nil]
        attribute(:event_type)
      end
    end
  end
end

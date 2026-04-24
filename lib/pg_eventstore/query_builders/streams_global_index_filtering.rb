# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class StreamsGlobalIndexFiltering < BasicFiltering
      # @return [String]
      PRIMARY_TABLE_NAME = 'streams_global_index'

      class << self

      end

      # @return [String]
      def to_table_name
        PRIMARY_TABLE_NAME
      end
    end
  end
end

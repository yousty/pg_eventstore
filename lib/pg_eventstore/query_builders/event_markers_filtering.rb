# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class EventMarkersFiltering
      include BasicFiltering

      PRIMARY_TABLE_NAME = 'event_markers'

      class << self
        # @param names [Array<String>]
        # @return [PgEventstore::SQLBuilder]
        def sql_builder_by_names(names)
          instance = new
          instance.add_names(names)
          instance.to_sql_builder
        end
      end

      def initialize
        @sql_builder = SQLBuilder.new.select("#{to_table_name}.id, #{to_table_name}.name").from(to_table_name)
      end

      def to_sql_builder
        @sql_builder
      end

      # @return [String]
      def to_table_name
        PRIMARY_TABLE_NAME
      end

      # @param names [Array<String>]
      # @return [void]
      def add_names(names)
        @sql_builder.where_or("#{to_table_name}.name = any(?::varchar[])", names)
      end

      # @param name [String]
      # @return [void]
      def add_name(name)
        @sql_builder.where_or("#{to_table_name}.name = ?", name)
      end
    end
  end
end

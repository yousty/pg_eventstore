# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class BasicFiltering
      def initialize
        @sql_builder = SQLBuilder.new.select("#{to_table_name}.*").from(to_table_name)
      end

      # @return [String]
      def to_table_name
        raise NotImplementedError
      end

      # @return [PgEventstore::SQLBuilder]
      def to_sql_builder
        @sql_builder
      end

      # @return [Array]
      def to_exec_params
        @sql_builder.to_exec_params
      end
    end
  end
end

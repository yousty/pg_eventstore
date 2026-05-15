# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    module BasicFiltering
      # @return [Hash<String => String, Symbol => String>]
      SQL_DIRECTIONS = {
        'asc' => 'ASC',
        'desc' => 'DESC',
        :asc => 'ASC',
        :desc => 'DESC',
        'Forwards' => 'ASC',
        'Backwards' => 'DESC',
      }.tap do |directions|
        directions.default = 'ASC'
      end.freeze

      # @return [String]
      def to_table_name
        raise NotImplementedError
      end

      # @return [PgEventstore::SQLBuilder]
      def to_sql_builder
        raise NotImplementedError
      end

      # @return [Array]
      def to_exec_params
        to_sql_builder.to_exec_params
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class EventSubscriptionPositionsFiltering
      include BasicFiltering

      PRIMARY_TABLE_NAME = 'event_subscription_positions'

      def initialize
        @sql_builder = SQLBuilder.new
        @sql_builder.select("#{to_table_name}.global_position, #{to_table_name}.subscription_position")
        @sql_builder.from(to_table_name)
      end

      def to_table_name
        PRIMARY_TABLE_NAME
      end

      def to_sql_builder
        @sql_builder
      end

      # @param positions [Array<Integer>]
      # @return [void]
      def by_global_positions(positions)
        @sql_builder.where('global_position = ANY(?::bigint[])', positions)
      end

      # @return [void]
      def max_subscription_position
        @sql_builder.unselect.select('max(subscription_position) as max_subscription_position')
      end
    end
  end
end

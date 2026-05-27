# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class SubscriptionEventsFiltering
      include BasicFiltering

      # @return [Integer]
      DEFAULT_LIMIT = 1_000

      class << self
        # @param options [Hash]
        # @return [PgEventstore::QueryBuilders::SubscriptionEventsFiltering]
        def build(id, options)
          index_filter = new(id)
          index_filter.from_position(options[:from_position])
          index_filter.to_position(options[:to_position])
          index_filter.add_limit(options[:max_count])
          index_filter
        end
      end

      def initialize(subscription_id)
        @subscription_id = subscription_id
        @sql_builder = SQLBuilder.new.select("#{to_table_name}.*").from(to_table_name)
      end

      def to_sql_builder
        @sql_builder
      end

      # @param position [Integer, nil]
      # @return [void]
      def from_position(position)
        return unless position

        @sql_builder.where("#{to_table_name}.global_position >= ?", position)
      end

      # @param position [Integer, nil]
      # @return [void]
      def to_position(position)
        return unless position

        @sql_builder.where("#{to_table_name}.global_position <= ?", position)
      end

      # @param limit [Integer, nil]
      # @return [void]
      def add_limit(limit)
        @sql_builder.limit(limit || DEFAULT_LIMIT)
      end

      # @return [String]
      def to_table_name
        "subscription_#{@subscription_id}"
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    # @!visibility private
    class SubscriptionEventsFiltering
      include BasicFiltering

      class << self
        # @param id [integer]
        # @param options [Hash]
        # @option options [Integer] :from_position
        # @option options [Integer] :to_position
        # @option options [Integer] :max_count
        # @return [PgEventstore::QueryBuilders::SubscriptionEventsFiltering]
        def build(id, options)
          index_filter = new(id)
          index_filter.from_position(options[:from_position])
          index_filter.to_position(options[:to_position])
          index_filter.add_limit(options[:max_count])
          index_filter
        end
      end

      # @param subscription_id [Integer]
      def initialize(subscription_id)
        @subscription_id = subscription_id
        @from_position = 0
        @to_position = 0
        @max_count = 0
        @sql_builder = SQLBuilder.new.select("#{to_table_name}.*")
        compute_from
      end

      def to_sql_builder
        compute_from
        @sql_builder
      end

      # @param position [Integer, nil]
      # @return [void]
      def from_position(position)
        raise ArgumentError, 'position must be valid number' unless position.is_a?(Integer)

        @from_position = position
      end

      # @param position [Integer, nil]
      # @return [void]
      def to_position(position)
        raise ArgumentError, 'position must be valid number' unless position.is_a?(Integer)

        @to_position = position
      end

      # @param limit [Integer, nil]
      # @return [void]
      def add_limit(limit)
        raise ArgumentError, 'limit must be valid number' unless limit.is_a?(Integer)

        @max_count = limit
      end

      # @return [String]
      def to_table_name
        "subscription_#{@subscription_id}"
      end

      private

      def compute_from
        @sql_builder.from(
          "#{to_table_name}(#{@from_position}, #{@to_position}, #{@max_count})",
          table_alias: to_table_name
        )
      end
    end
  end
end

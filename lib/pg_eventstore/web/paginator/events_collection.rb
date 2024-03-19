# frozen_string_literal: true

module PgEventstore
  module Paginator
    class EventsCollection < BaseCollection
      SQL_DIRECTIONS = {
        'asc' => :asc,
        'desc' => :desc
      }.tap do |directions|
        directions.default = :desc
      end.freeze
      PER_PAGE = %w[10 20 50 100 1000].to_h { [_1, _1.to_i] }.tap do |per_page|
        per_page.default = 10
      end.freeze
      # Max number of events after which we don't perform the exact count and keep the estimate count instead because of
      # the potential performance degradation.
      MAX_NUMBER_TO_COUNT = 10_000

      # @return [Array<PgEventstore::Event>]
      def collection
        @_collection ||= PgEventstore.client(config_name).read(
          PgEventstore::Stream.all_stream,
          options: options.merge(
            from_position: starting_id, max_count: per_page, direction: order, resolve_link_tos: true
          ),
          middlewares: []
        )
      end

      # @return [Integer, nil]
      def next_page_starting_id
        return unless collection.size == per_page

        from_position = event_global_position(collection.first)
        sql_builder = QueryBuilders::EventsFiltering.all_stream_filtering(
          options.merge(from_position: from_position, max_count: 1, direction: order)
        ).to_sql_builder.unselect.select('global_position').offset(per_page)
        global_position(sql_builder)
      end

      # @return [Integer, nil]
      def prev_page_starting_id
        from_position = event_global_position(collection.first) || starting_id
        sql_builder = QueryBuilders::EventsFiltering.all_stream_filtering(
          options.merge(from_position: from_position, max_count: 1, direction: order == :asc ? :desc : :asc)
        ).to_sql_builder.unselect.select('global_position').offset(per_page)
        global_position(sql_builder)
      end

      # @return [Integer]
      def total_count
        @_total_count ||=
          begin
            sql_builder =
              QueryBuilders::EventsFiltering.all_stream_filtering(options).
                to_sql_builder.remove_limit.remove_group.remove_order
            count = estimate_count(sql_builder)
            return count if count > MAX_NUMBER_TO_COUNT

            regular_count(sql_builder)
          end
      end

      private

      # @param event [PgEventstore::Eventg]
      # @return [integer, nil]
      def event_global_position(event)
        event&.link&.global_position || event&.global_position
      end

      # @param sql_builder [PgEventstore::SQLBuilder]
      # @return [Integer]
      def estimate_count(sql_builder)
        sql, params = sql_builder.to_exec_params
        connection.with do |conn|
          conn.exec_params("EXPLAIN #{sql}", params)
        end.to_a.first['QUERY PLAN'].match(/rows=(\d+)/)[1].to_i
      end

      # @param sql_builder [PgEventstore::SQLBuilder]
      # @return [Integer]
      def regular_count(sql_builder)
        sql_builder.unselect.select('count(*) as count_all')

        connection.with do |conn|
          conn.exec_params(*sql_builder.to_exec_params)
        end.to_a.first['count_all']
      end

      # @return [Integer, nil]
      def global_position(sql_builder)
        connection.with do |conn|
          conn.exec_params(*sql_builder.to_exec_params)
        end.to_a.dig(0, 'global_position')
      end
    end
  end
end

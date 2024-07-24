# frozen_string_literal: true

module PgEventstore
  module Web
    module Paginator
      class EventTypesCollection < BaseCollection
        # @return [Integer]
        PER_PAGE = 10

        # @return [Array<Hash<String => String>>]
        def collection
          @_collection ||=
            begin
              sql_builder =
                SQLBuilder.new.select('event_type').from('partitions').
                  where('context is not null and stream_name is not null').
                  group('event_type').order("event_type #{order}").limit(per_page)
              sql_builder.where("event_type #{direction_operator} ?", starting_id) if starting_id
              sql_builder.where('event_type ilike ?', "#{options[:query]}%")
              connection.with do |conn|
                conn.exec_params(*sql_builder.to_exec_params)
              end.to_a
            end
        end

        # @return [String, nil]
        def next_page_starting_id
          return unless collection.size == per_page

          starting_id = collection.first['event_type']
          sql_builder =
            SQLBuilder.new.select('event_type').from('partitions').
              where('context is not null and stream_name is not null').
              where("event_type #{direction_operator} ?", starting_id).
              where('event_type ilike ?', "#{options[:query]}%").
              group('event_type').order("event_type #{order}").limit(1).offset(per_page)

          connection.with do |conn|
            conn.exec_params(*sql_builder.to_exec_params)
          end.to_a.dig(0, 'event_type')
        end

        private

        # @return [String]
        def direction_operator
          order == :asc ? '>=' : '<='
        end
      end
    end
  end
end

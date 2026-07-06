# frozen_string_literal: true

module PgEventstore
  module Web
    module Paginator
      class MarkersCollection < BaseCollection
        # @return [Integer]
        PER_PAGE = 10

        # @return [Array<Hash<String => String>>]
        def collection
          @collection ||=
            begin
              sql_builder = SQLBuilder.new.select('name').from('event_markers')
              sql_builder.where("name #{direction_operator} ?", starting_id) if starting_id
              sql_builder.where('name like ?', "#{options[:query]}%")
              sql_builder.order("name #{order}").limit(per_page)
              connection.with do |conn|
                conn.exec_params(*sql_builder.to_exec_params)
              end.to_a
            end
        end

        # @return [String, nil]
        def next_page_starting_id
          return unless collection.size == per_page

          starting_id = collection.first['name']
          sql_builder = SQLBuilder.new.select('name').from('event_markers')
          sql_builder.where("name #{direction_operator} ?", starting_id)
          sql_builder.where('name like ?', "#{options[:query]}%")
          sql_builder.order("name #{order}").limit(1).offset(per_page)

          connection.with do |conn|
            conn.exec_params(*sql_builder.to_exec_params)
          end.to_a.dig(0, 'name')
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

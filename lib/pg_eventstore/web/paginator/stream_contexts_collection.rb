# frozen_string_literal: true

module PgEventstore
  module Web
    module Paginator
      class StreamContextsCollection < BaseCollection
        # @return [Integer]
        PER_PAGE = 10

        # @return [Array<Hash<String => String>>]
        def collection
          @_collection ||=
            begin
              sql_builder =
                SQLBuilder.new.select('context').from('partitions').
                  where('stream_name is null and event_type is null').
                  limit(per_page).order("context #{order}")
              sql_builder.where("context #{direction_operator} ?", starting_id) if starting_id
              sql_builder.where('context ilike ?', "%#{options[:query]}%")
              connection.with do |conn|
                conn.exec_params(*sql_builder.to_exec_params)
              end.to_a
            end
        end

        # @return [String, nil]
        def next_page_starting_id
          return unless collection.size == per_page

          starting_id = collection.first['context']
          sql_builder =
            SQLBuilder.new.select('context').from('partitions').where('stream_name is null and event_type is null').
              where("context #{direction_operator} ?", starting_id).where('context ilike ?', "%#{options[:query]}%").
              limit(1).offset(per_page).order("context #{order}")

          connection.with do |conn|
            conn.exec_params(*sql_builder.to_exec_params)
          end.to_a.dig(0, 'context')
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

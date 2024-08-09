# frozen_string_literal: true

module PgEventstore
  module Web
    module Paginator
      class StreamNamesCollection < BaseCollection
        # @return [Integer]
        PER_PAGE = 10

        # @return [Array<Hash<String => String>>]
        def collection
          @_collection ||=
            begin
              sql_builder =
                SQLBuilder.new.select('stream_name').from('partitions').
                  where('event_type is null and context = ?', options[:context]).
                  where('stream_name ilike ?', "%#{options[:query]}%")
              sql_builder.where("stream_name #{direction_operator} ?", starting_id) if starting_id
              sql_builder.limit(per_page).order("stream_name #{order}")
              connection.with do |conn|
                conn.exec_params(*sql_builder.to_exec_params)
              end.to_a
            end
        end

        # @return [String, nil]
        def next_page_starting_id
          return unless collection.size == per_page

          starting_id = collection.first['stream_name']
          sql_builder =
            SQLBuilder.new.select('stream_name').from('partitions').
              where("stream_name #{direction_operator} ?", starting_id).
              where('stream_name ilike ?', "%#{options[:query]}%").
              where('event_type is null and context = ?', options[:context]).
              limit(1).offset(per_page).order("stream_name #{order}")

          connection.with do |conn|
            conn.exec_params(*sql_builder.to_exec_params)
          end.to_a.dig(0, 'stream_name')
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

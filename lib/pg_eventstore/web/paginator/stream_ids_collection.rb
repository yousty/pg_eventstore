# frozen_string_literal: true

module PgEventstore
  module Web
    module Paginator
      class StreamIdsCollection < BaseCollection
        # @return [Integer]
        PER_PAGE = 10

        # @return [Array<Hash<String => String>>]
        def collection
          @collection ||=
            begin
              sql_builder = SQLBuilder.new.select('stream_id').from('events')
              sql_builder.where('context = ? and stream_name = ?', options[:context], options[:stream_name])
              sql_builder.where('stream_id like ?', "#{options[:query]}%")
              sql_builder.where("stream_id #{direction_operator} ?", starting_id) if starting_id
              sql_builder.group('stream_id').limit(per_page).order("stream_id #{order}")
              connection.with do |conn|
                conn.exec_params(*sql_builder.to_exec_params)
              end.to_a
            end
        end

        # @return [String, nil]
        def next_page_starting_id
          return unless collection.size == per_page

          starting_id = collection.first['stream_id']
          sql_builder = SQLBuilder.new.select('stream_id').from('events')
          sql_builder.where("stream_id #{direction_operator} ?", starting_id)
          sql_builder.where('stream_id like ?', "#{options[:query]}%")
          sql_builder.where('context = ? and stream_name = ?', options[:context], options[:stream_name])
          sql_builder.group('stream_id').limit(1).offset(per_page).order("stream_id #{order}")

          connection.with do |conn|
            conn.exec_params(*sql_builder.to_exec_params)
          end.to_a.dig(0, 'stream_id')
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

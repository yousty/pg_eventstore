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
              sql_builder = streams_index_sql_builder(from_id: starting_id)
              sql_builder.limit(per_page)

              connection.with do |conn|
                conn.exec_params(*sql_builder.to_exec_params)
              end.to_a
            end
        end

        # @return [String, nil]
        def next_page_starting_id
          return unless collection.size == per_page

          sql_builder = streams_index_sql_builder(from_id: collection.first['stream_id'])
          sql_builder.limit(1).offset(per_page)

          connection.with do |conn|
            conn.exec_params(*sql_builder.to_exec_params)
          end.to_a.dig(0, 'stream_id')
        end

        private

        def partitions_sql_builder
          filters = QueryBuilders::Filters::Collection.from_options(
            { filter: { streams: [{ context: options[:context], stream_name: options[:stream_name] }] } }
          )
          QueryBuilders::PartitionsFiltering.assemble_sql_builder(filters, scope: :stream_name).unselect.select('id')
        end

        def streams_index_sql_builder(from_id: nil)
          sql_builder = SQLBuilder.new.select('stream_id')
          sql_builder.from(QueryBuilders::StreamsGlobalIndexFiltering::PRIMARY_TABLE_NAME)
          sql_builder.where('partition_id = ?', partitions_sql_builder)
          sql_builder.where('stream_id like ?', "#{options[:query]}%")
          sql_builder.where("stream_id #{direction_operator} ?", from_id) if from_id
          sql_builder.order("stream_id #{order}")
        end

        # @return [String]
        def direction_operator
          order == :asc ? '>=' : '<='
        end
      end
    end
  end
end

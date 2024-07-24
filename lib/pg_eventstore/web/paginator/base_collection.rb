# frozen_string_literal: true

module PgEventstore
  module Web
    module Paginator
      class BaseCollection
        # @!attribute config_name
        #   @return [Symbol]
        attr_reader :config_name
        # @!attribute starting_id
        #   @return [String, Integer, nil]
        attr_reader :starting_id
        # @!attribute per_page
        #   @return [Integer]
        attr_reader :per_page
        # @!attribute order
        #   @return [Symbol]
        attr_reader :order
        # @!attribute options
        #   @return [Hash]
        attr_reader :options

        # @param config_name [Symbol]
        # @param starting_id [String, Integer, nil]
        # @param per_page [Integer]
        # @param order [Symbol] :asc or :desc
        # @param options [Hash] additional options to filter the collection
        def initialize(config_name, starting_id:, per_page:, order:, options: {})
          @config_name = config_name
          @starting_id = starting_id
          @per_page = per_page
          @order = order
          @options = options
        end

        # @return [Array]
        def collection
          raise NotImplementedError
        end

        # @return [Integer]
        def count
          collection.size
        end

        # @return [String, Integer, nil]
        def next_page_starting_id
          raise NotImplementedError
        end

        # @return [String, Integer, nil]
        def prev_page_starting_id
          raise NotImplementedError
        end

        # @return [Integer]
        def total_count
          raise NotImplementedError
        end

        private

        # @return [PgEventstore::Connection]
        def connection
          PgEventstore.connection(config_name)
        end
      end
    end
  end
end

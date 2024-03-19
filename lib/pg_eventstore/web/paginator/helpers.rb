# frozen_string_literal: true

module PgEventstore
  module Paginator
    module Helpers
      def previous_page_link(collection)
        id = collection.prev_page_starting_id
        disabled = id ? '' : 'disabled'
        <<~HTML
          <li class="page-item #{disabled}">
            <a class="page-link" href="#{build_starting_id_link(id)}" tabindex="-1">Previous</a>
          </li>
        HTML
      end

      def next_page_link(collection)
        id = collection.next_page_starting_id
        disabled = id ? '' : 'disabled'
        <<~HTML
          <li class="page-item #{disabled}">
            <a class="page-link" href="#{build_starting_id_link(id)}" tabindex="-1">Next</a>
          </li>
        HTML
      end

      def first_page_link
        encoded_params = Rack::Utils.build_nested_query(params.slice(*(params.keys - ['starting_id'])))
        <<~HTML
          <li class="page-item">
            <a class="page-link" href="#{build_path(encoded_params)}" tabindex="-1">First</a>
          </li>
        HTML
      end

      def per_page_url(per_page)
        encoded_params = Rack::Utils.build_nested_query(params.merge(per_page: per_page))
        build_path(encoded_params)
      end

      def total_count(number)
        prefix =
          if number > Paginator::EventsCollection::MAX_NUMBER_TO_COUNT
            "Estimate count: "
          else
            "Total count: "
          end
        number = number_with_delimiter(number)
        prefix + number
      end

      def number_with_delimiter(number, delimiter: ',')
        number = number.to_s
        symbols_to_skip = number.size % 3
        parts = []
        parts.push(number[0...symbols_to_skip]) unless symbols_to_skip.zero?
        parts.push(*number[symbols_to_skip..].scan(/\d{3}/))
        parts.join(delimiter)
      end

      private

      def build_starting_id_link(starting_id)
        return 'javascript: void(0);' unless starting_id

        encoded_params = Rack::Utils.build_nested_query(params.merge(starting_id: starting_id))
        build_path(encoded_params)
      end

      def build_path(encoded_params)
        return request.path if encoded_params.empty?

        "#{request.path}?#{encoded_params}"
      end
    end
  end
end

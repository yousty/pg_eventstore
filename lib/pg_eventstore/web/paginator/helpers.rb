# frozen_string_literal: true

module PgEventstore
  module Web
    module Paginator
      module Helpers
        # @param collection [PgEventstore::Web::Paginator::BaseCollection]
        # @return [String]
        def previous_page_link(collection)
          id = collection.prev_page_starting_id
          disabled = id ? '' : 'disabled'
          <<~HTML
          <li class="page-item #{disabled}">
            <a class="page-link" href="#{build_starting_id_link(id)}" tabindex="-1">Previous</a>
          </li>
        HTML
        end

        # @param collection [PgEventstore::Web::Paginator::BaseCollection]
        # @return [String]
        def next_page_link(collection)
          id = collection.next_page_starting_id
          disabled = id ? '' : 'disabled'
          <<~HTML
          <li class="page-item #{disabled}">
            <a class="page-link" href="#{build_starting_id_link(id)}" tabindex="-1">Next</a>
          </li>
        HTML
        end

        # @return [String]
        def first_page_link
          path = build_path(params.slice(*(params.keys - ['starting_id'])))
          <<~HTML
          <li class="page-item">
            <a class="page-link" href="#{path}" tabindex="-1">First</a>
          </li>
        HTML
        end

        # @param per_page [String] string representation of items per page. E.g. "10", "20", etc.
        # @return [String]
        def per_page_url(per_page)
          build_path(params.merge(per_page: per_page))
        end

        # @param order [String] "asc"/"desc"
        # @return [String]
        def sort_url(order)
          build_path(params.merge(order: order))
        end

        def resolve_link_tos_url(should_resolve)
          build_path(params.merge(resolve_link_tos: should_resolve))
        end

        # @param number [Integer] total number of events by the current filter
        # @return [String]
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

        # Takes an integer and adds delimiters in there. E.g 1002341 becomes this "1,002,341"
        # @param number [Integer]
        # @param delimiter [String]
        # @return [String] number with delimiters
        def number_with_delimiter(number, delimiter: ',')
          number = number.to_s
          symbols_to_skip = number.size % 3
          parts = []
          parts.push(number[0...symbols_to_skip]) unless symbols_to_skip.zero?
          parts.push(*number[symbols_to_skip..].scan(/\d{3}/))
          parts.join(delimiter)
        end

        # @param event [PgEventstore::Event]
        # @return [String]
        def stream_path(event)
          build_path(
            {
              filter: {
                streams: [
                  {
                    context: escape_empty_string(event.stream.context),
                    stream_name: escape_empty_string(event.stream.stream_name),
                    stream_id: escape_empty_string(event.stream.stream_id)
                  }
                ]
              }
            }
          )
        end

        # @param str [String]
        # @return [String]
        def empty_characters_fallback(str)
          return str unless str.strip == ''

          '<i>Non-printable characters</i>'
        end

        private

        # @param starting_id [String, Integer, nil]
        # @return [String]
        def build_starting_id_link(starting_id)
          return 'javascript: void(0);' unless starting_id

          build_path(params.merge(starting_id: starting_id))
        end

        # @param params [Hash, Array]
        # @return [String]
        def build_path(params)
          encoded_params = Rack::Utils.build_nested_query(params)
          return request.path if encoded_params.empty?

          "#{request.path}?#{encoded_params}"
        end
      end
    end
  end
end

# frozen_string_literal: true

module RequestsHelper
  # Extracts uuids from the response body
  # @return [Array<String>]
  def rendered_event_ids
    last_response.body.scan(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}/i)
  end

  def parsed_body
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    last_response.body
  end
end

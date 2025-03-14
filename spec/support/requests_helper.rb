# frozen_string_literal: true

module RequestsHelper
  # Extracts uuids from the response body
  # @return [Array<String>]
  def rendered_event_ids
    last_response.body.scan(/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}/i)
  end

  def nokogiri_body
    Nokogiri::HTML.parse(last_response.body)
  end

  def parsed_body
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    last_response.body
  end

  # @return [Hash]
  def flash_message
    flash_message = last_response.headers['set-cookie']&.split(';')&.find do |str|
      str.start_with?(PgEventstore::Web::Application::COOKIES_FLASH_MESSAGE_KEY)
    end
    return unless flash_message

    flash_message = flash_message.gsub("#{PgEventstore::Web::Application::COOKIES_FLASH_MESSAGE_KEY}=", '')
    JSON.parse(Base64.urlsafe_decode64(CGI.unescape(flash_message)), symbolize_names: true)
  end
end

# frozen_string_literal: true

module PgEventstore
  module Commands
    module EventModifiers
      # Defines how to transform regular event into a link event
      # @!visibility private
      class PrepareLinkEvent
        class << self
          # @param event [PgEventstore::Event]
          # @param revision [Integer]
          # @return [PgEventstore::Event]
          def call(event, revision)
            Event.new(link_id: event.id, type: Event::LINK_TYPE, stream_revision: revision).tap do |e|
              %i[link_id type stream_revision].each { |attr| e.readonly!(attr) }
            end
          end
        end
      end
    end
  end
end

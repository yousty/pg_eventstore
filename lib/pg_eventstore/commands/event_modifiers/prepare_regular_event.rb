# frozen_string_literal: true

module PgEventstore
  module Commands
    module EventModifiers
      # Defines how to transform regular event before appending it to the stream
      # @!visibility private
      class PrepareRegularEvent
        # @param event [PgEventstore::Event]
        # @param revision [Integer]
        # @return [PgEventstore::Event]
        def call(event, revision)
          event.class.new(
            id: event.id, data: event.data, metadata: event.metadata, type: event.type, stream_revision: revision
          ).tap do |e|
            %i[link_global_position link_partition_id stream_revision].each { |attr| e.readonly!(attr) }
          end
        end
      end
    end
  end
end

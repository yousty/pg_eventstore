# frozen_string_literal: true

module PgEventstore
  module Commands
    module EventModifiers
      # Defines how to transform regular event before appending it to the stream
      # @!visibility private
      class PrepareRegularEvent
        # @param serializer [PgEventstore::EventSerializer]
        def initialize(serializer)
          @serializer = serializer
        end

        # @param event [PgEventstore::Event]
        # @return [PgEventstore::Event]
        def call(event)
          event = event.dup
          %i[link_global_position link_partition_id].each { |attr| event.readonly!(attr) }
          @serializer.serialize(event)
          event
        end
      end
    end
  end
end

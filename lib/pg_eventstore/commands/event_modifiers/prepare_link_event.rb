# frozen_string_literal: true

module PgEventstore
  module Commands
    module EventModifiers
      # Defines how to transform regular event into a link event
      # @!visibility private
      class PrepareLinkEvent
        attr_reader :partition_queries, :partitions

        # @param partition_queries [PgEventstore::PartitionQueries]
        def initialize(partition_queries)
          @partitions = {}
          @partition_queries = partition_queries
        end
        # @param event [PgEventstore::Event]
        # @param revision [Integer]
        # @return [PgEventstore::Event]
        def call(event, revision)
          Event.new(
            link_id: event.id, link_partition_id: partition_id(event), type: Event::LINK_TYPE, stream_revision: revision
          ).tap do |e|
            %i[link_id link_partition_id type stream_revision].each { |attr| e.readonly!(attr) }
          end
        end

        private

        # @param event [PgEventstore::Event] persisted event
        # @return [Integer] partition id
        # @raise [PgEventstore::MissingPartitionError]
        def partition_id(event)
          partition_id = @partitions.dig(event.stream.context, event.stream.stream_name, event.type)
          return partition_id if partition_id

          partition_id = partition_queries.event_type_partition(event.stream, event.type)['id']
          @partitions[event.stream.context] ||= {}
          @partitions[event.stream.context][event.stream.stream_name] ||= {}
          @partitions[event.stream.context][event.stream.stream_name][event.type] = partition_id
        end
      end
    end
  end
end

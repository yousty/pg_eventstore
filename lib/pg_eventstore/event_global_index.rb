# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class EventGlobalIndex < Struct.new(:global_position, :stream_revision, :context_partition_id,
                                       :stream_name_partition_id, :event_type_partition_id, :streams_global_index_id,
                                       keyword_init: true)
  end
end

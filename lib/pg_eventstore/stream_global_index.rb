# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class StreamGlobalIndex < Struct.new(:id, :partition_id, :stream_id, :stream_revision, :starting_position,
                                       keyword_init: true)
    INITIAL_STARTING_POSITION = -1
  end
end

# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  module Chunks
  end
end

require_relative 'chunks/chunk'
require_relative 'chunks/events_index_chunk'
require_relative 'chunks/repository'

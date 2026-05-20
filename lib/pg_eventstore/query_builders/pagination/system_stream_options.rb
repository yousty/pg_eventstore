# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Pagination
      class SystemStreamOptions < Struct.new(:from_position, :to_position, :direction, :max_count)
      end
    end
  end
end

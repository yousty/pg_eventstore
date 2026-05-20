# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Pagination
      class RegularStreamOptions < Struct.new(:from_revision, :to_revision, :direction, :max_count)
      end
    end
  end
end

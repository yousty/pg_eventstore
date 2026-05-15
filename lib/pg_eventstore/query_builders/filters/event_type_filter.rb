# frozen_string_literal: true

module PgEventstore
  module QueryBuilders
    module Filters
      class EventTypeFilter < Struct.new(:value, :prefix)
        def prefix?
          prefix
        end

        def to_sql_value
          prefix? ? "#{value}%" : value
        end
      end
    end
  end
end

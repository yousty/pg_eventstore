# frozen_string_literal: true

require_relative 'regular_stream_options'
require_relative 'system_stream_options'

module PgEventstore
  module QueryBuilders
    module Pagination
      class StreamOptions
        class << self
          def from_options(options)
            SystemStreamOptions.new(**options.slice(*SystemStreamOptions.members))
          end

          def from_stream_and_options(stream, options)
            return SystemStreamOptions.new(**options.slice(*SystemStreamOptions.members)) if stream.system?

            RegularStreamOptions.new(**options.slice(*RegularStreamOptions.members))
          end
        end
      end
    end
  end
end

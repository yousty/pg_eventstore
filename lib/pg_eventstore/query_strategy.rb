# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  module QueryStrategy
    # @return [PG::Result]
    def exec(*args)
      raise NotImplementedError
    end

    # @return [PG::Result]
    def exec_params(*args)
      raise NotImplementedError
    end
  end
end

require_relative 'query_strategy/async'
require_relative 'query_strategy/foreground'

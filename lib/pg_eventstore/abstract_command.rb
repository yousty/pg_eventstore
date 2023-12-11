# frozen_string_literal: true

module PgEventstore
  class AbstractCommand
    attr_reader :queries
    private :queries

    # @param queries [PgEventstore::Queries]
    def initialize(queries)
      @queries = queries
    end

    def call(*, **)
      raise NotImplementedError, "Implement #call in your child class."
    end
  end
end

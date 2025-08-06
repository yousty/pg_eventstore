# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  class AbstractCommand
    # @!attribute queries
    #   @return [PgEventstore::Queries]
    attr_reader :queries
    private :queries

    # @param queries [PgEventstore::Queries]
    def initialize(queries)
      @queries = queries
    end

    def call(*, **)
      raise NotImplementedError, 'Implement #call in your child class.'
    end
  end
end

# frozen_string_literal: true

require_relative 'event_serializer'
require_relative 'pgresult_deserializer'
require_relative 'queries'

module PgEventstore
  class AbstractCommand
    attr_reader :queries
    private :queries

    # @param connection [PgEventstore::Connection]
    # @param middlewares [Array<Object<#serialize, #deserialize>>]
    # @param event_class_resolver [#call]
    def initialize(connection, middlewares, event_class_resolver)
      @queries = Queries.new(
        connection,
        EventSerializer.new(middlewares),
        PgresultDeserializer.new(middlewares, event_class_resolver)
      )
    end

    def call(*, **)
      raise NotImplementedError, "Implement #call in your child class."
    end
  end
end

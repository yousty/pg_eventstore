# frozen_string_literal: true

require_relative 'commands'

module PgEventstore
  class Client
    attr_reader :config
    private :config

    # @param config [PgEventstore::Config]
    def initialize(config)
      @config = config
    end
    
    # Append the event or multiple events to the stream. This operation is atomic, meaning that no other event can be
    # appended by parallel process between the given events.
    # @param stream [PgEventstore::Stream]
    # @param events_or_event [PgEventstore::Event, Array<PgEventstore::Event>]
    # @param options [Hash]
    # @option options [Integer] :expected_revision provide your own revision number
    # @option options [Symbol] :expected_revision provide one of next values: :any, :no_stream or :stream_exists
    # @return [PgEventstore::Event, Array<PgEventstore::Event>] persisted event(s)
    # @raise [PgEventstore::WrongExpectedVersionError]
    def append_to_stream(stream, events_or_event, options: {}, skip_middlewares: false, &blk)
      result =
        Commands::Append.
          new(connection, middlewares(skip_middlewares), config.event_class_resolver).
          call(stream, *events_or_event, options: options, &blk)
      events_or_event.is_a?(Array) ? result : result.first
    end

    # Allows you to make several different commands atomic by wrapping then into a block.
    # Example:
    #   PgEventstore.client.multiple do
    #     PgEventstore.client.append_to_stream(...)
    #     PgEventstore.client.append_to_stream(...)
    #   end
    #
    # @return the result of the given block
    def multiple(&blk)
      Commands::Multiple.new(connection, middlewares, config.event_class_resolver).call(&blk)
    end

    private

    # @param skip_middlewares [Boolean]
    # @return [Array<Object<#serialize, #deserialize>>]
    def middlewares(skip_middlewares = false)
      return config.middlewares unless skip_middlewares

      []
    end

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(config.name)
    end
  end
end

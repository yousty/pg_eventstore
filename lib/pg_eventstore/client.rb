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
    # @param skip_middlewares [Boolean] whether to skip middlewares. Defaults to false
    # @return [PgEventstore::Event, Array<PgEventstore::Event>] persisted event(s)
    # @raise [PgEventstore::WrongExpectedVersionError]
    def append_to_stream(stream, events_or_event, options: {}, skip_middlewares: false)
      result =
        Commands::Append.
          new(connection, middlewares(skip_middlewares), config.event_class_resolver).
          call(stream, *events_or_event, options: options)
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

    # Read events from the specific stream or from "all" stream.
    # @param stream [PgEventstore::Stream]
    # @param options [Hash] request options
    # @option options [String] :direction read direction - 'Forwards' or 'Backwards'
    # @option options [Integer] :from_revision a starting revision number. **Use this option when stream name is a
    #   normal stream name**
    # @option options [Integer, Symbol] :from_position a starting global position number. **Use this option when reading
    #   from "all" stream**
    # @option options [Integer] :max_count max number of events to return in one response. Defaults to config.per_page
    # @option options [Boolean] :resolve_link_tos When using projections to create new events you
    #   can set whether the generated events are pointers to existing events. Setting this value
    #   to true tells EventStoreDB to return the event as well as the event linking to it.
    # @option options [Hash] :filter provide it to filter events. You can filter by: stream and by event type. Filtering
    #   by stream is only available when reading from "all" stream.
    #   Examples:
    #     # Filtering by stream's context. This will return all events which #context is 'User
    #     PgEventstore.client.read(
    #       PgEventstore::Stream.all_stream,
    #       options: { filter: { streams: [{ context: 'User' }] } }
    #     )
    #
    #     # Filtering by several stream's contexts. This will return all events which #context is either 'User' or
    #     # 'Profile'
    #     PgEventstore.client.read(
    #       PgEventstore::Stream.all_stream,
    #       options: { filter: { streams: [{ context: 'User' }, { context: 'Profile' }] } }
    #     )
    #
    #     # Filtering by a mix of specific stream and a context. This will return all events which #context is 'User' or
    #     # events belonging to the stream with { context: 'Profile', stream_name: 'ProfileFields', stream_id: '123' }
    #     PgEventstore.client.read(
    #       PgEventstore::Stream.all_stream,
    #       options: {
    #         filter: {
    #           streams: [
    #             { context: 'User' },
    #             { context: 'Profile', stream_name: 'ProfileFields', stream_id: '123' }
    #           ]
    #         }
    #       }
    #     )
    #
    #     # Filtering the a mix of context and event type
    #     PgEventstore.client.read(
    #       PgEventstore::Stream.all_stream,
    #       options: { filter: { streams: [{ context: 'User' }], event_types: ['MyAwesomeEvent'] } }
    #     )
    #
    #     # Filtering by specific event when reading from the specific stream
    #     PgEventstore.client.read(stream, { options: { filter: { event_types: ['MyAwesomeEvent'] } } })
    # @param skip_middlewares [Boolean] whether to skip middlewares. Defaults to false
    # @return [Array<PgEventstore::Event>]
    # @raise [PgEventstore::StreamNotFoundError]
    def read(stream, options: {}, skip_middlewares: false)
      Commands::Read.
        new(connection, middlewares(skip_middlewares), config.event_class_resolver).
        call(stream, options: options)
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

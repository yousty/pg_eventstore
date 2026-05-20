# frozen_string_literal: true

require_relative 'event_serializer'
require_relative 'event_deserializer'

module PgEventstore
  class Client
    # @!attribute config
    #   @return [PgEventstore::Config]
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
    # @param middlewares [Array, nil] provide a list of middleware names to override a config's middlewares
    # @return [PgEventstore::Event, Array<PgEventstore::Event>] persisted event(s)
    # @raise [PgEventstore::WrongExpectedRevisionError]
    def append_to_stream(stream, events_or_event, options: {}, middlewares: nil)
      middlewares = self.middlewares(middlewares)
      event_modifier = Commands::EventModifiers::PrepareRegularEvent.new(EventSerializer.new(middlewares))
      queries = Queries.new(
        partitions: partition_queries,
        events: event_queries,
        transactions: transaction_queries,
        events_global_index: events_global_index_queries,
        streams_global_index: streams_global_index_queries
      )
      result = Commands::Append.new(queries).call(
        stream, *events_or_event, event_modifier:, deserializer: event_deserializer(middlewares), options:
      )
      events_or_event.is_a?(Array) ? result : result.first
    end

    # Allows you to make several different commands atomic by wrapping then into a block. Order of events, produced by
    # multiple commands, belonging to different streams - is unbreakable. So, if you append event1 to stream1 and
    # event2 to stream2 using this method, then thet appear in the same order in the "all" stream.
    # Example:
    #   PgEventstore.client.multiple do
    #     PgEventstore.client.read(...)
    #     PgEventstore.client.append_to_stream(...)
    #     PgEventstore.client.append_to_stream(...)
    #   end
    #
    # @param read_only [Boolean] whether transaction is read-only. Running mutation queries within read-only transaction
    #   will result in exception
    # @return the result of the given block
    def multiple(read_only: false, &)
      Commands::Multiple.new(Queries.new(transactions: transaction_queries)).call(read_only:, &)
    end

    # Read events from the specific stream or from "all" stream.
    # @param stream [PgEventstore::Stream]
    # @param options [Hash] request options
    # @option options [String] :direction read direction. Allowed values are "Forwards", "Backwards", "asc", "desc",
    #   :asc, :desc
    # @option options [Integer] :from_revision a starting revision number. **Use this option when stream name is a
    #   normal stream name**
    # @option options [Integer] :to_revision ending revision number. **Use this option when stream name is a
    #   normal stream name**
    # @option options [Integer] :from_position a starting global position number. **Use this option when reading
    #   from "all" stream**
    # @option options [Integer] :to_position ending global position number. **Use this option when reading from
    #   "all" stream**
    # @option options [Integer] :max_count max number of events to return in one response. Defaults to config.max_count
    # @option options [Boolean] :resolve_link_tos When using projections to create new events you
    #   can set whether the generated events are pointers to existing events. Setting this option to true tells
    #   PgEventstore to return the original event instead a link event.
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
    #     # Filtering a mix of context and event type
    #     PgEventstore.client.read(
    #       PgEventstore::Stream.all_stream,
    #       options: { filter: { streams: [{ context: 'User' }], event_types: ['MyAwesomeEvent'] } }
    #     )
    #
    #     # Filtering by specific event when reading from the specific stream
    #     PgEventstore.client.read(stream, options: { filter: { event_types: ['MyAwesomeEvent'] } })
    # @param middlewares [Array, nil] provide a list of middleware names to override a config's middlewares
    # @return [Array<PgEventstore::Event>]
    # @raise [PgEventstore::StreamNotFoundError]
    def read(stream, options: {}, middlewares: nil)
      queries = Queries.new(
        events_global_index: events_global_index_queries,
        streams_global_index: streams_global_index_queries
      )
      Commands::Read.new(queries).call(
        stream,
        deserializer: event_deserializer(middlewares(middlewares)),
        options: { max_count: config.max_count }.merge(options)
      )
    end

    # @see {#read} for the detailed docs
    # @param stream [PgEventstore::Stream]
    # @param options [Hash] request options
    # @param middlewares [Array, nil]
    # @return [Enumerator] enumerator will yield Array<PgEventstore::Event>
    def read_paginated(stream, options: {}, middlewares: nil)
      cmd_class = stream.system? ? Commands::SystemStreamReadPaginated : Commands::RegularStreamReadPaginated
      queries = Queries.new(
        events_global_index: events_global_index_queries,
        streams_global_index: streams_global_index_queries
      )
      cmd_class.new(queries).call(
        stream,
        deserializer: event_deserializer(middlewares(middlewares)),
        options: { max_count: config.max_count }.merge(options)
      )
    end

    # Takes a stream, event types filter and returns most recent(or very first - depending on :direction option) events,
    # one of each given type. The result size is almost always less than or equal to event types list size, so passing
    # :max_count option does not take any effect. In case if event of same type appears in different context/stream
    # name - it will be counted as a different event, thus, may appear several times in the result, scoped to each
    # context and stream name in the result. Useful when implementing Dynamic Consistency Boundaries.
    # @see {#read} for the detailed docs
    # @param stream [PgEventstore::Stream]
    # @param options [Hash] request options
    # @param middlewares [Array, nil]
    # @return [Array<PgEventstore::Event>]
    def read_grouped(stream, options: {}, middlewares: nil)
      queries = Queries.new(
        events_global_index: events_global_index_queries,
        streams_global_index: streams_global_index_queries
      )
      Commands::ReadGrouped.new(queries).call(
        stream, deserializer: event_deserializer(middlewares(middlewares)), options:
      )
    end

    # @param options [Hash] request options
    # @option options [String] :direction read direction. Allowed values are "Forwards", "Backwards", "asc", "desc",
    #   :asc, :desc
    # @option options [Integer] :from_position a starting global position number
    # @option options [Integer] :max_count max number of streams to return in one response. Defaults to config.max_count
    # @return [Array<PgEventstore::Stream>]
    def read_streams(options: {})
      queries = Queries.new(streams_global_index: streams_global_index_queries)
      Commands::ReadStreams.new(queries).call(options: { max_count: config.max_count }.merge(options))
    end

    # @param options [Hash] request options
    # @option options [String] :direction read direction. Allowed values are "Forwards", "Backwards", "asc", "desc",
    #   :asc, :desc
    # @option options [Integer] :from_position a starting global position number
    # @option options [Integer] :max_count max number of streams to return in one response. Defaults to config.max_count
    # @return [Enumerator] yields Array<PgEventstore::Stream>
    def read_streams_paginated(options: {})
      queries = Queries.new(streams_global_index: streams_global_index_queries)
      Commands::ReadStreamsPaginated.new(queries).call(options: { max_count: config.max_count }.merge(options))
    end

    # Links event from one stream into another stream. You can later access it by providing :resolve_link_tos option
    # when reading from a stream. Only existing events can be linked.
    # @param stream [PgEventstore::Stream]
    # @param events_or_event [PgEventstore::Event, Array<PgEventstore::Event>]
    # @param options [Hash]
    # @option options [Integer] :expected_revision provide your own revision number
    # @option options [Symbol] :expected_revision provide one of next values: :any, :no_stream or :stream_exists
    # @param middlewares [Array] provide a list of middleware names to use. Defaults to empty array, meaning no
    #   middlewares will be applied to the "link" event
    # @return [PgEventstore::Event, Array<PgEventstore::Event>] persisted event(s)
    # @raise [PgEventstore::WrongExpectedRevisionError]
    def link_to(stream, events_or_event, options: {}, middlewares: [])
      middlewares = self.middlewares(middlewares)
      event_modifier = Commands::EventModifiers::PrepareLinkEvent.new(
        partition_queries, EventSerializer.new(middlewares)
      )
      queries = Queries.new(
        partitions: partition_queries,
        events: event_queries,
        transactions: transaction_queries,
        events_global_index: events_global_index_queries,
        streams_global_index: streams_global_index_queries
      )
      result = Commands::LinkTo.new(queries).call(
        stream, *events_or_event, event_modifier:, deserializer: event_deserializer(middlewares), options:
      )
      events_or_event.is_a?(Array) ? result : result.first
    end

    def stream_revision(stream)
      queries = Queries.new(streams_global_index: streams_global_index_queries)
      Commands::StreamRevision.new(queries).call(stream)
    end

    def streams(options: {})

    end

    private

    # @param middlewares [Array, nil]
    # @return [Array<PgEventstore::Middleware>]
    def middlewares(middlewares = nil)
      return config.middlewares.values unless middlewares

      config.middlewares.slice(*middlewares).values
    end

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(config.name)
    end

    # @return [PgEventstore::PartitionQueries]
    def partition_queries
      PartitionQueries.new(connection)
    end

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end

    # @return [PgEventstore::EventQueries]
    def event_queries
      EventQueries.new(connection)
    end

    # @param middlewares [Array<Middleware>]
    # @return [PgEventstore::EventDeserializer]
    def event_deserializer(middlewares)
      EventDeserializer.new(middlewares, config.event_class_resolver)
    end

    # @return [PgEventstore::EventsGlobalIndexQueries]
    def events_global_index_queries
      EventsGlobalIndexQueries.new(connection, QueryStrategy::Foreground.new(connection))
    end

    # @return [PgEventstore::EventsGlobalIndexQueries]
    def streams_global_index_queries
      StreamsGlobalIndexQueries.new(connection, QueryStrategy::Foreground.new(connection))
    end
  end
end

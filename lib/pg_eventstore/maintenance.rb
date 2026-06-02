# frozen_string_literal: true

module PgEventstore
  class Maintenance
    # @!attribute config
    #   @return [PgEventstore::Config]
    attr_reader :config
    private :config

    # @param config [PgEventstore::Config]
    def initialize(config)
      @config = config
    end

    # @param stream [PgEventstore::Stream]
    # @return [Boolean] whether a stream was deleted successfully
    def delete_stream(stream)
      queries = Queries.new(maintenance: maintenance_queries)
      Commands::DeleteStream.new(queries).call(stream)
    end

    # @param event [PgEventstore::Event] persisted event
    # @return [Boolean] whether an event was deleted successfully
    def delete_event(event, force: false)
      queries = Queries.new(maintenance: maintenance_queries, events_global_index: events_global_index_queries)
      Commands::DeleteEvent.new(queries).call(event, force:)
    end

    private

    # @return [PgEventstore::MaintenanceQueries]
    def maintenance_queries
      MaintenanceQueries.new(connection)
    end

    # @return [PgEventstore::TransactionQueries]
    def transaction_queries
      TransactionQueries.new(connection)
    end

    # @return [PgEventstore::Connection]
    def connection
      PgEventstore.connection(config.name)
    end

    # @return [PgEventstore::EventsGlobalIndexQueries]
    def events_global_index_queries
      EventsGlobalIndexQueries.new(connection, QueryStrategy::Foreground.new(connection))
    end
  end
end

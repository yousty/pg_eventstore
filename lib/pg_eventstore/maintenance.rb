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
      Commands::DeleteStream.new(
        Queries.new(transactions: transaction_queries, maintenance: maintenance_queries)
      ).call(stream)
    end

    # @param event [PgEventstore::Event] persisted event
    # @return [Boolean] whether an event was deleted successfully
    def delete_event(event, force: false)
      Commands::DeleteEvent.new(
        Queries.new(transactions: transaction_queries, maintenance: maintenance_queries)
      ).call(event, force: force)
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
  end
end

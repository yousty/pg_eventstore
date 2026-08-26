# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      module Collectors
        # Base class for metric collectors. A collector runs read-only queries and returns an array of
        # {MetricFamily} objects.
        class Base
          # Milliseconds. Guards the store from a metrics query that got stuck - a scrape then fails visibly instead
          # of piling up on the database.
          # @return [Integer]
          STATEMENT_TIMEOUT = 5_000

          # @!attribute connection
          #   @return [PgEventstore::Connection]
          attr_reader :connection
          # @!attribute sets
          #   @return [Array<String>]
          attr_reader :sets
          private :connection, :sets

          # @param connection [PgEventstore::Connection]
          # @param sets [Array<String>] subscription sets to report on; an empty array means all of them
          def initialize(connection, sets: [])
            @connection = connection
            @sets = sets
          end

          # @return [Array<PgEventstore::Web::Metrics::MetricFamily>]
          def call
            raise NotImplementedError, "#{self.class} must implement #call"
          end

          private

          # @return [PgEventstore::SQLBuilder]
          def subscriptions_sql_builder
            sql_builder = SQLBuilder.new.from('subscriptions', table_alias: 's')
            sql_builder.order('s.set, s.name')
            sql_builder.where('s.set = any(?::varchar[])', sets) if sets.any?
            sql_builder
          end

          # @return [Array<Hash>]
          def with_safe_conn
            transaction_queries.transaction(:read_committed, read_only: true) do
              connection.with do |conn|
                conn.exec("set local statement_timeout to #{STATEMENT_TIMEOUT}")
                yield conn
              end
            end.to_a
          end

          # @param row [Hash]
          # @return [Hash<Symbol => String>]
          def subscription_labels(row)
            { set: row['set'], name: row['name'] }
          end

          # @return [PgEventstore::TransactionQueries]
          def transaction_queries
            TransactionQueries.new(connection)
          end
        end
      end
    end
  end
end

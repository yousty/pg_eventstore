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

          # @param sql [String]
          # @param params [Array<Object>]
          # @return [Array<Hash>]
          def rows(sql, params = [])
            connection.with do |conn|
              conn.transaction do
                conn.exec("set local statement_timeout to #{STATEMENT_TIMEOUT}")
                conn.exec_params(sql, params).to_a
              end
            end
          end

          # Scopes a query to the requested subscription sets.
          #
          # Rows of the subscriptions table are never removed, so a long-lived database accumulates handlers that
          # were renamed, removed, or never ran against it. Scoping by set keeps a scrape - and the dashboards built
          # on it - to the subscriptions of a single application, and is backed by idx_subscriptions_set_and_name.
          # @return [String] SQL condition
          def sets_condition
            return 'true' if sets.empty?

            "s.set in (#{sets.each_index.map { "$#{_1 + 1}" }.join(', ')})"
          end

          # @return [Array<String>] bind params matching #sets_condition
          def sets_params
            sets
          end

          # @param row [Hash]
          # @return [Hash<Symbol => String>]
          def subscription_labels(row)
            { set: row['set'], name: row['name'] }
          end
        end
      end
    end
  end
end

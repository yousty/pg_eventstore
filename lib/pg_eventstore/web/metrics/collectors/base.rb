# frozen_string_literal: true

module PgEventstore
  module Web
    module Metrics
      module Collectors
        # Base class for metric collectors. A collector runs a single read-only query and returns an array of
        # {MetricFamily} objects.
        class Base
          # Milliseconds. Guards the store from a metrics query that got stuck - a scrape then fails visibly instead
          # of piling up on the database.
          # @return [Integer]
          STATEMENT_TIMEOUT = 5_000
          # Seconds. A subscription is considered alive - and thus worth reporting - when it is either locked by a
          # subscriptions set or was updated recently. Everything else is a leftover registry row (a handler that was
          # renamed, removed or never ran on this database) - reporting those would drown the dashboard in dead
          # series.
          # @return [Integer]
          LIVENESS_WINDOW = 600

          # @param connection [PgEventstore::Connection]
          def initialize(connection)
            @connection = connection
          end

          # @return [Array<PgEventstore::Web::Metrics::MetricFamily>]
          def call
            raise NotImplementedError, "#{self.class} must implement #call"
          end

          private

          # @param sql [String]
          # @return [Array<Hash>]
          def rows(sql)
            @connection.with do |conn|
              conn.transaction do
                conn.exec("set local statement_timeout to #{STATEMENT_TIMEOUT}")
                conn.exec(sql).to_a
              end
            end
          end

          # @return [String] SQL condition matching alive subscriptions
          def liveness_condition
            <<~SQL.strip
              (s.locked_by is not null or s.updated_at > (now() at time zone 'utc') - interval '#{LIVENESS_WINDOW} seconds')
            SQL
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

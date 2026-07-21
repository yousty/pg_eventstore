# frozen_string_literal: true

class ConfigHelper
  class << self
    def reconfigure
      # Reset PgEventstore internal state
      PgEventstore.send(:init_variables)
      PgEventstore.configure do |pg_conf|
        pg_conf.pg_uri = test_db_uri
        pg_conf.connection_pool_size = 20
      end
      setup_logger
    end

    def test_db_uri
      ENV.fetch('PG_EVENTSTORE_URI', 'postgresql://postgres:postgres@localhost:6432/eventstore_test')
    end

    private

    def setup_logger
      if ENV['DEBUG'] == '1'
        logger = Logger.new($stdout)
        logger.level = :debug
        logger.formatter = proc do |_severity, _time, _progname, msg|
          "#{Niceql::Prettifier.prettify_sql(msg)}\n"
        end
        PgEventstore.logger = logger
      else
        PgEventstore.logger = nil
      end
    end
  end
end

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
    end

    def test_db_uri
      ENV.fetch('PG_EVENTSTORE_URI', 'postgresql://postgres:postgres@localhost:5532/eventstore_test')
    end
  end
end

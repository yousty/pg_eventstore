# frozen_string_literal: true

class CLIHelper
  class << self
    attr_accessor :current_subscription_manager
    attr_writer :tmp_file_suffix

    def non_running_subscriptions_file_path
      "/tmp/initialized_subscriptions_#{tmp_file_suffix}.rb"
    end

    def running_subscriptions_file_path
      "/tmp/running_subscriptions_#{tmp_file_suffix}.rb"
    end

    def stub_consts_file_path
      "/tmp/stub_constsn_#{tmp_file_suffix}.rb"
    end

    def persist_running_subscriptions_file
      content = File.read('spec/support/cli_assets/running_subscriptions.rb.erb')
      PgEventstore::Utils.write_to_file(running_subscriptions_file_path, ERB.new(content).result)
    end

    def persist_non_running_subscriptions_file
      content = File.read('spec/support/cli_assets/initialized_subscriptions.rb.erb')
      PgEventstore::Utils.write_to_file(non_running_subscriptions_file_path, ERB.new(content).result)
    end

    def persist_stub_consts_file
      content = File.read('spec/support/cli_assets/stub_consts.rb.erb')
      PgEventstore::Utils.write_to_file(stub_consts_file_path, ERB.new(content).result)
    end

    def remove_running_subscriptions_file
      PgEventstore::Utils.remove_file(running_subscriptions_file_path)
    end

    def remove_non_running_subscriptions_file
      PgEventstore::Utils.remove_file(non_running_subscriptions_file_path)
    end

    def remove_stub_consts_file
      PgEventstore::Utils.remove_file(stub_consts_file_path)
    end

    def tmp_file_suffix
      @tmp_file_suffix ||= SecureRandom.hex(8)
    end

    def processed_events
      begin
        JSON.parse(redis.get("processed-events").to_s, symbolize_names: true)
      rescue JSON::ParserError
        []
      end
    end

    def process_event(event)
      events = processed_events
      events.push(event.attributes_hash)
      redis.set("processed-events", events.to_json)
    end

    def clean_up
      current_subscription_manager&.stop
      remove_running_subscriptions_file
      remove_non_running_subscriptions_file
      remove_stub_consts_file
      self.current_subscription_manager = nil
      self.tmp_file_suffix = nil
    end

    def redis
      require 'redis'
      Redis.new(host: 'localhost', port: '6579')
    end
  end
end

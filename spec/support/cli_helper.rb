# frozen_string_literal: true

class CLIHelper
  class << self
    attr_accessor :current_subscription_manager, :current_processed_events
    attr_writer :tmp_file_suffix

    def non_running_subscriptions_file_path
      "/tmp/initialized_subscriptions_#{tmp_file_suffix}.rb"
    end

    def running_subscriptions_file_path
      "/tmp/running_subscriptions_#{tmp_file_suffix}.rb"
    end

    def persist_running_subscriptions_file
      file = File.new(running_subscriptions_file_path, 'w')
      content = File.read('spec/support/cli_assets/running_subscriptions.rb.erb')
      file.write(ERB.new(content).result)
      file.close
    end

    def persist_non_running_subscriptions_file
      file = File.new(non_running_subscriptions_file_path, 'w')
      content = File.read('spec/support/cli_assets/initialized_subscriptions.rb.erb')
      file.write(ERB.new(content).result)
      file.close
    end

    def remove_running_subscriptions_file
      File.delete(running_subscriptions_file_path)
    rescue Errno::ENOENT
    end

    def remove_non_running_subscriptions_file
      File.delete(non_running_subscriptions_file_path)
    rescue Errno::ENOENT
    end

    def tmp_file_suffix
      @tmp_file_suffix ||= SecureRandom.hex(8)
    end

    def clean_up
      current_subscription_manager&.stop
      remove_running_subscriptions_file
      remove_non_running_subscriptions_file
      self.current_subscription_manager = nil
      self.current_processed_events = nil
      self.tmp_file_suffix = nil
    end
  end
end

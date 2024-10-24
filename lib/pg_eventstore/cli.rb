# frozen_string_literal: true

require 'optparse'
require_relative 'cli/parsers/base_options'
require_relative 'cli/parsers/base_options_parser'
require_relative 'cli/parsers/default_options'
require_relative 'cli/parsers/default_options_parser'
require_relative 'cli/parsers/subscription_options'
require_relative 'cli/parsers/subscription_options_parser'
require_relative 'cli/try_unlock_subscriptions_set'
require_relative 'cli/commands/base_command'
require_relative 'cli/commands/help'
require_relative 'cli/commands/start_subscriptions'
require_relative 'cli/commands/stop_subscriptions'

module PgEventstore
  module CLI
    OPTIONS_PARSER = {
      "subscriptions" => [SubscriptionOptionsParser, SubscriptionOptions]
    }.tap do |directions|
      directions.default = [DefaultOptionsParser, DefaultOptions]
    end.freeze

    COMMANDS = {
      ["subscriptions", "start"].freeze => Commands::StartSubscriptions,
      ["subscriptions", "stop"].freeze => Commands::StopSubscriptions
    }.freeze

    class << self
      # @param args [Array<String>]
      def execute(args)
        options_parser_class, options_class = OPTIONS_PARSER[args[0]]
        command, parsed_options = options_parser_class.new(ARGV, options_class.new).parse
        return Commands::Help.new(parsed_options).call if parsed_options.help
        return COMMANDS[command].new(parsed_options).call if COMMANDS[command]

        _, parsed_options = options_parser_class.new(['-h'], options_class.new).parse
        Commands::Help.new(parsed_options).call
      end
    end
  end
end

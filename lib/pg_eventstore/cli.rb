# frozen_string_literal: true

require 'optparse'
require_relative 'cli/parsers'
require_relative 'cli/parser_options'
require_relative 'cli/try_unlock_subscriptions_set'
require_relative 'cli/exit_codes'
require_relative 'cli/commands'

module PgEventstore
  module CLI
    OPTIONS_PARSER = {
      'subscriptions' => [Parsers::SubscriptionParser, ParserOptions::SubscriptionOptions].freeze,
    }.tap do |directions|
      directions.default = [Parsers::DefaultParser, ParserOptions::DefaultOptions].freeze
    end.freeze

    COMMANDS = {
      %w[subscriptions start].freeze => Commands::StartSubscriptionsCommand,
      %w[subscriptions stop].freeze => Commands::StopSubscriptionsCommand,
    }.freeze

    class << self
      # @return [PgEventstore::Callbacks]
      def callbacks
        @callbacks ||= Callbacks.new
      end

      # @param args [Array<String>]
      # @return [Integer] exit code
      def execute(args)
        options_parser_class, options_class = OPTIONS_PARSER[args[0]]
        command, parsed_options = options_parser_class.new(args, options_class.new).parse
        return Commands::HelpCommand.new(parsed_options).call if parsed_options.help
        return COMMANDS[command].new(parsed_options).call if COMMANDS[command]

        _, parsed_options = options_parser_class.new(['-h'], options_class.new).parse
        Commands::HelpCommand.new(parsed_options).call
      end
    end
  end
end

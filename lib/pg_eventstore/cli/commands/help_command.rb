# frozen_string_literal: true

module PgEventstore
  module CLI
    module Commands
      # @!visibility private
      class HelpCommand
        attr_reader :options

        # @param options [PgEventstore::CLI::ParserOptions::BaseOptions]
        def initialize(options)
          @options = options
        end

        # @return [Integer] exit code
        def call
          puts options.help
          ExitCodes::SUCCESS
        end
      end
    end
  end
end

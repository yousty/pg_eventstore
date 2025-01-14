# frozen_string_literal: true

module PgEventstore
  module CLI
    module Parsers
      class BaseParser
        class << self
          # @return [String]
          def banner
            raise NotImplementedError
          end
        end

        attr_reader :args, :options

        # @param args [Array<String>]
        # @param options [PgEventstore::CLI::ParserOptions::BaseOptions]
        def initialize(args, options)
          @args = args
          @options = options
          @parser = ::OptionParser.new(self.class.banner)
        end

        # @return [Array<Array<String>, PgEventstore::CLI::ParserOptions::BaseOptions>] list of commands and parsed
        #   options
        def parse
          @options.attach_parser_handlers(@parser)
          [@parser.parse(args), @options]
        end
      end
    end
  end
end

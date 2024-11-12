# frozen_string_literal: true

module PgEventstore
  module CLI
    module ParserOptions
      class BaseOptions
        include Extensions::OptionsExtension

        option(:help, metadata: Metadata.new(short: '-h', long: '--help', description: 'Prints this help'))
        option(
          :requires,
          metadata: Metadata.new(
            short: '-rFILE_PATH',
            long: '--require=FILE_PATH',
            description: 'Ruby files to load. You can provide this option multiple times to load more files.'
          )
        ) do
          []
        end

        # @param parser [OptionParser]
        # @return [void]
        def attach_parser_handlers(parser)
          parser.on(*to_parser_opts(:help)) do
            self.help = parser.to_s
          end
          parser.on(*to_parser_opts(:requires)) do |path|
            requires.push(path)
          end
        end

        # @param option [Symbol]
        # @return [Array<String>]
        def to_parser_opts(option)
          option(option).metadata.to_parser_opts
        end

        # @param option [Symbol]
        # @return [PgEventstore::Extensions::OptionsExtension::Option]
        def option(option)
          self.class.options[option]
        end
      end
    end
  end
end

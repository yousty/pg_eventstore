# frozen_string_literal: true

module PgEventstore
  module CLI
    module ParserOptions
      # @!visibility private
      class Metadata
        include Extensions::OptionsExtension

        option(:short)
        option(:long)
        option(:description)

        # @return [Array<String>]
        def to_parser_opts
          [short, long, description]
        end

        # @return [Integer]
        def hash
          to_parser_opts.hash
        end

        # @param other [Object]
        # @return [Boolean]
        def ==(other)
          return false unless other.is_a?(Metadata)

          to_parser_opts == other.to_parser_opts
        end
        alias eql? ==
      end
    end
  end
end

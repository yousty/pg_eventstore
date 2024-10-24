# frozen_string_literal: true

module PgEventstore
  module CLI
    module Commands
      class BaseCommand
        attr_reader :options

        # @param options [PgEventstore::CLI::BaseOptions]
        def initialize(options)
          @options = options
        end

        # @return [void]
        def call
          load_external_files
        end

        private

        # @return [void]
        def load_external_files
          options.requires.each do |file|
            require file
          end
        end
      end
    end
  end
end

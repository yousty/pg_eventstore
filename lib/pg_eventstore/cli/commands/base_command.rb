# frozen_string_literal: true

module PgEventstore
  module CLI
    module Commands
      # @!visibility private
      class BaseCommand
        # @!visibility private
        module BaseCommandActions
          # @return [Integer] exit code
          def call
            load_external_files
            super
          end

          private

          # @return [void]
          def load_external_files
            options.requires.each do |file_path|
              require(file_path)
            end
          end
        end

        class << self
          def inherited(klass)
            super
            klass.prepend BaseCommandActions
          end
        end

        attr_reader :options

        # @param options [PgEventstore::CLI::ParserOptions::BaseOptions]
        def initialize(options)
          @options = options
        end

        # @return [Integer] exit code
        def call
          raise NotImplementedError
        end
      end
    end
  end
end

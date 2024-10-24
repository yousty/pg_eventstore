# frozen_string_literal: true

module PgEventstore
  module CLI
    module Commands
      class Help < BaseCommand
        # @return [void]
        def call
          puts options.help
        end
      end
    end
  end
end

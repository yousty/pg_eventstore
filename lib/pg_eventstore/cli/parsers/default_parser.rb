# frozen_string_literal: true

module PgEventstore
  module CLI
    module Parsers
      class DefaultParser < BaseParser
        class << self
          # @return [String]
          def banner
            <<~TEXT
              Usage: pg-eventstore [options]
                     pg-eventstore [command]

                Commands:
                  subscriptions     Start, stop subscriptions

                Options:
            TEXT
          end
        end
      end
    end
  end
end

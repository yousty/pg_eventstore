# frozen_string_literal: true

module PgEventstore
  module CLI
    module Parsers
      class SubscriptionParser < BaseParser
        class << self
          # @return [String]
          def banner
            <<~TEXT
              Usage: pg-eventstore subscriptions [command] [options]

                Commands:
                  start     Start subscriptions. Example: pg-eventstore subscriptions start -r lib/my_subscriptions.rb
                  stop      Stop subscriptions. Example: pg-eventstore subscriptions stop

                Options:
            TEXT
          end
        end
      end
    end
  end
end

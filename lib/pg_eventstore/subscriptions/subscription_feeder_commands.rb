# frozen_string_literal: true

require_relative 'subscription_feeder_commands/base'
require_relative 'subscription_feeder_commands/restore'
require_relative 'subscription_feeder_commands/start_all'
require_relative 'subscription_feeder_commands/stop'
require_relative 'subscription_feeder_commands/stop_all'

module PgEventstore
  # @!visibility private
  module SubscriptionFeederCommands
    extend Extensions::CommandClassLookupExtension
  end
end

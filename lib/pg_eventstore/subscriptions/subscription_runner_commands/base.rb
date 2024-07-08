# frozen_string_literal: true

module PgEventstore
  module SubscriptionRunnerCommands
    # @!visibility private
    class Base
      include Extensions::OptionsExtension
      include Extensions::BaseCommandExtension

      # @!attribute id
      #   @return [Integer]
      attribute(:id)
      # @!attribute name
      #   @return [String]
      attribute(:name) { self.class.name.split('::').last }
      # @!attribute subscription_id
      #   @return [Integer]
      attribute(:subscription_id)
      # @!attribute subscriptions_set_id
      #   @return [Integer]
      attribute(:subscriptions_set_id)
      # @!attribute data
      #   @return [Hash]
      attribute(:data) { {} }
      # @!attribute created_at
      #   @return [Time]
      attribute(:created_at)

      # @param subscription_runner [PgEventstore::SubscriptionRunner]
      # @return [void]
      def exec_cmd(subscription_runner)
        # Implement it in the subclass
      end
    end
  end
end

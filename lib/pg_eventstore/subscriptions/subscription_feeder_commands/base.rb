# frozen_string_literal: true

module PgEventstore
  module SubscriptionFeederCommands
    # @!visibility private
    class Base
      include Extensions::OptionsExtension
      include Extensions::BaseCommandExtension

      # @!attribute id
      #   @return [Integer, nil]
      attribute(:id)
      # @!attribute name
      #   @return [String]
      attribute(:name) { self.class.name.split('::').last }
      # @!attribute subscriptions_set_id
      #   @return [Integer, nil]
      attribute(:subscriptions_set_id)
      # @!attribute data
      #   @return [Hash, nil]
      attribute(:data) { {} }
      # @!attribute created_at
      #   @return [Time, nil]
      attribute(:created_at)

      # @param subscription_feeder [PgEventstore::SubscriptionFeeder]
      # @return [void]
      def exec_cmd(subscription_feeder)
        # Implement it in the subclass
      end
    end
  end
end

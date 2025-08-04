# frozen_string_literal: true

module PgEventstore
  module Web
    module Subscriptions
      class SubscriptionsToSetAssociation
        # @!attribute subscriptions_set
        #   @return [Array<PgEventstore::SubscriptionsSet>]
        attr_reader :subscriptions_set
        # @!attribute subscriptions
        #   @return [Array<PgEventstore::Subscription>]
        attr_reader :subscriptions

        # @param subscriptions_set [Array<PgEventstore::SubscriptionsSet>]
        # @param subscriptions [Array<PgEventstore::Subscription>]
        def initialize(subscriptions_set:, subscriptions:)
          @subscriptions_set = subscriptions_set
          @subscriptions = subscriptions
        end

        # @return [Hash{PgEventstore::SubscriptionsSet => Array<PgEventstore::Subscription>}]
        # rubocop:disable Lint/RedundantWithObject,Lint/UnexpectedBlockArity
        def association
          @association ||=
            begin
              association = subscriptions.group_by do |subscription|
                set = subscriptions_set.find { |set| set.id == subscription.locked_by }
                set || PgEventstore::SubscriptionsSet.new
              end
              (subscriptions_set - association.keys).each_with_object(association) do |subscriptions_set|
                association[subscriptions_set] = []
              end
            end
        end
        # rubocop:enable Lint/RedundantWithObject,Lint/UnexpectedBlockArity
      end
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  # Defines ruby's representation of subscriptions_set record.
  class SubscriptionsSet
    include Extensions::UsingConnectionExtension
    include Extensions::OptionsExtension

    class << self
      # @param attrs [Hash]
      # @return [PgEventstore::SubscriptionsSet]
      def create(attrs)
        new(**subscriptions_set_queries.create(attrs))
      end

      private

      # @return [PgEventstore::SubscriptionsSetQueries]
      def subscriptions_set_queries
        SubscriptionsSetQueries.new(connection)
      end
    end

    # @!attribute id
    #   @return [Integer, nil] It is used to lock the Subscription by updating Subscription#locked_by attribute
    attribute(:id)
    # @!attribute name
    #   @return [String, nil] name of the set
    attribute(:name)
    # @!attribute state
    #   @return [String, nil]
    attribute(:state)
    # @!attribute restart_count
    #   @return [Integer, nil] the number of SubscriptionsSet's restarts after its failure
    attribute(:restart_count)
    # @!attribute max_restarts_number
    #   @return [Integer, nil] maximum number of times the SubscriptionsSet can be restarted
    attribute(:max_restarts_number)
    # @!attribute time_between_restarts
    #   @return [Integer, nil] interval in seconds between retries of failed SubscriptionsSet
    attribute(:time_between_restarts)
    # @!attribute last_restarted_at
    #   @return [Time, nil] last time the SubscriptionsSet was restarted
    attribute(:last_restarted_at)
    # @!attribute last_error
    #   @return [Hash, nil] the information about
    #     last error caused when pulling Subscriptions events.
    attribute(:last_error)
    # @!attribute last_error_occurred_at
    #   @return [Time, nil] the time when the last error occurred
    attribute(:last_error_occurred_at)
    # @!attribute created_at
    #   @return [Time, nil]
    attribute(:created_at)
    # @!attribute updated_at
    #   @return [Time, nil]
    attribute(:updated_at)

    # @param attrs [Hash]
    # @return [Hash]
    def assign_attributes(attrs)
      attrs.each do |attr, value|
        public_send("#{attr}=", value)
      end
    end

    # @param attrs [Hash]
    # @return [Hash]
    def update(attrs)
      assign_attributes(subscriptions_set_queries.update(id, attrs))
    end

    # @return [void]
    def delete
      subscriptions_set_queries.delete(id)
    end

    # Dup the current object without assigned connection
    # @return [PgEventstore::SubscriptionsSet]
    def dup
      SubscriptionsSet.new(**Utils.deep_dup(options_hash))
    end

    # @return [PgEventstore::SubscriptionsSet]
    def reload
      assign_attributes(subscriptions_set_queries.find!(id))
      self
    end

    # @return [Integer]
    def hash
      id.hash
    end

    # @param other [Object]
    # @return [Boolean]
    def eql?(other)
      return false unless other.is_a?(SubscriptionsSet)

      hash == other.hash
    end

    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(SubscriptionsSet)

      id == other.id
    end

    private

    # @return [PgEventstore::SubscriptionsSetQueries]
    def subscriptions_set_queries
      SubscriptionsSetQueries.new(self.class.connection)
    end
  end
end

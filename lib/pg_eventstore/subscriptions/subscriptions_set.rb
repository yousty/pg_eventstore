# frozen_string_literal: true

module PgEventstore
  class SubscriptionsSet
    include Extensions::UsingConnectionExtension
    include Extensions::OptionsExtension

    class << self
      # @param name [String]
      # @return [PgEventstore::SubscriptionsSet]
      def create(name:)
        new(**subscriptions_set_queries.create(name: name))
      end

      private

      # @return [PgEventstore::SubscriptionsSetQueries]
      def subscriptions_set_queries
        SubscriptionsSetQueries.new(connection)
      end
    end

    # @!attribute id
    #   @return [String] UUIDv4
    attribute(:id)
    # @!attribute name
    #   @return [String]
    attribute(:name)
    # @!attribute state
    #   @return [String]
    attribute(:state)
    # @!attribute restarts_count
    #   @return [Integer] the number of SubscriptionsSet's restarts after its failure
    attribute(:restarts_count)
    # @!attribute max_restarts_number
    #   @return [Integer] maximum number of times the SubscriptionsSet can be restarted
    attribute(:max_restarts_number)
    # @!attribute last_restarted_at
    #   @return [Time, nil] last time the SubscriptionsSet was restarted
    attribute(:last_restarted_at)
    # @!attribute last_error
    #   @return [Hash, nil] the information about last error caused when processing events by the SubscriptionsSet
    attribute(:last_error)
    # @!attribute last_error_occurred_at
    #   @return [Time, nil] the time when the last error occurred
    attribute(:last_error_occurred_at)
    # @!attribute created_at
    #   @return [Time]
    attribute(:created_at)
    # @!attribute updated_at
    #   @return [Time]
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
      subscriptions_set_queries.update(self, attrs)
    end

    def delete
      subscriptions_set_queries.delete(id)
    end

    private

    def subscriptions_set_queries
      SubscriptionsSetQueries.new(self.class.connection)
    end
  end
end

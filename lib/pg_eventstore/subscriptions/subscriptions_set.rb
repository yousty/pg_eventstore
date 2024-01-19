# frozen_string_literal: true

module PgEventstore
  # Defines ruby's representation of subscriptions_set record.
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
    #   @return [String] UUIDv4. It is used to lock the Subscription by updating Subscription#locked_by attribute
    attribute(:id)
    # @!attribute name
    #   @return [String] name of the set
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
    #   @return [Hash{'class' => String, 'message' => String, 'backtrace' => Array<String>}, nil] the information about
    #     last error caused when pulling Subscriptions events.
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

    private

    # @return [PgEventstore::SubscriptionsSetQueries]
    def subscriptions_set_queries
      SubscriptionsSetQueries.new(self.class.connection)
    end
  end
end

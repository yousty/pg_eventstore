# frozen_string_literal: true

module PgEventstore
  # Defines ruby's representation of subscriptions record.
  # @!visibility private
  class Subscription
    include Extensions::UsingConnectionExtension
    include Extensions::OptionsExtension

    class << self
      # @param set [String]
      # @param name [String]
      # @param options [Hash]
      # @param chunk_query_interval [Integer]
      # @param max_restarts_number [Integer]
      # @return [PgEventstore::Subscription]
      def init_by(set:, name:, options:, chunk_query_interval:, max_restarts_number:)
        new(
          set: set, name: name, options: options,
          chunk_query_interval: chunk_query_interval, max_restarts_number: max_restarts_number
        )
      end

      private

      # @return [PgEventstore::SubscriptionQueries]
      def subscription_queries
        SubscriptionQueries.new(connection)
      end
    end

    # @!attribute id
    #   @return [Integer]
    attribute(:id)
    # @!attribute set
    #   @return [String] Subscription's set. Subscription should have unique pair of set and name.
    attribute(:set)
    # @!attribute name
    #   @return [String] Subscription's name. Subscription should have unique pair of set and name.
    attribute(:name)
    # @!attribute events_processed_total
    #   @return [Integer] total number of events, processed by this subscription
    attribute(:events_processed_total)
    # @!attribute options
    #   @return [Hash] subscription's options to be used to query events. See {SubscriptionManager#subscribe} for the
    #     list of available options
    attribute(:options)
    # @!attribute current_position
    #   @return [Integer, nil] current Subscription's position. It is updated automatically each time an event is processed
    attribute(:current_position)
    # @!attribute state
    #   @return [String, nil] current Subscription's state. It is updated automatically during Subscription's life cycle.
    #     See {ObjectState::STATES} for possible values.
    attribute(:state)
    # @!attribute events_processing_frequency
    #   @return [Float, nil] a speed of the subscription. Divide 1 by this value to determine how much events are
    #     processed by the Subscription per second.
    attribute(:events_processing_frequency)
    # @!attribute restarts_count
    #   @return [Integer] the number of Subscription's restarts after its failure
    attribute(:restarts_count)
    # @!attribute max_restarts_number
    #   @return [Integer] maximum number of times the Subscription can be restarted
    attribute(:max_restarts_number)
    # @!attribute last_restarted_at
    #   @return [Time, nil] last time the Subscription was restarted
    attribute(:last_restarted_at)
    # @!attribute last_error
    #   @return [Hash, nil] the information about last error caused when processing events by the Subscription.
    attribute(:last_error)
    # @!attribute last_error_occurred_at
    #   @return [Time, nil] the time when the last error occurred
    attribute(:last_error_occurred_at)
    # @!attribute chunk_query_interval
    #   @return [Integer] determines how often to pull events for the given Subscription in seconds
    attribute(:chunk_query_interval)
    # @!attribute chunk_query_interval
    #   @return [Time] shows the time when last time events were fed to the event's processor
    attribute(:last_chunk_fed_at)
    # @!attribute last_chunk_greatest_position
    #   @return [Integer, nil] shows the greatest global_position of the last event in the last chunk fed to the event's
    #     processor
    attribute(:last_chunk_greatest_position)
    # @!attribute locked_by
    #   @return [String, nil] UUIDv4. The id of subscription manager which obtained the lock of the Subscription. _nil_
    #     value means that the Subscription isn't locked yet by any subscription manager.
    attribute(:locked_by)
    # @!attribute created_at
    #   @return [Time]
    attribute(:created_at)
    # @!attribute updated_at
    #   @return [Time]
    attribute(:updated_at)

    def options=(val)
      @options = Utils.deep_transform_keys(val, &:to_sym)
    end

    # @param attrs [Hash]
    # @return [Hash]
    def update(attrs)
      subscription_queries.update(self, attrs)
    end

    # @param attrs [Hash]
    # @return [Hash]
    def assign_attributes(attrs)
      attrs.each do |attr, value|
        public_send("#{attr}=", value)
      end
    end

    # @return [PgEventstore::Subscription]
    def persist
      assign_attributes(subscription_queries.find_or_create_by(set: set, name: name))
      self
    end

    # Locks the Subscription by the given lock id
    # @return [PgEventstore::Subscription]
    def lock!(lock_id)
      assign_attributes(subscription_queries.lock!(id, lock_id))
      update(
        options: options,
        restarts_count: 0,
        last_restarted_at: nil,
        max_restarts_number: max_restarts_number,
        chunk_query_interval: chunk_query_interval,
        last_chunk_fed_at: Time.at(0),
        last_chunk_greatest_position: nil,
        state: ObjectState::STATES[:initial]
      )
      self
    end

    def unlock!
      assign_attributes(subscription_queries.unlock!(id, locked_by))
    end

    def reload
      attrs = subscription_queries.find_by(id: id)
      raise "Subscription #{id} does not exist any more!" unless attrs

      assign_attributes(attrs.transform_keys(&:to_s))
    end

    private

    def subscription_queries
      SubscriptionQueries.new(self.class.connection)
    end
  end
end

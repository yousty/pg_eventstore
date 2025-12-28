# frozen_string_literal: true

module PgEventstore
  # Defines ruby's representation of subscriptions record.
  class Subscription
    include Extensions::UsingConnectionExtension
    include Extensions::OptionsExtension

    # Determines the minimal allowed value of events pull frequency of the particular subscription. You can find similar
    # constant - SubscriptionFeeder::EVENTS_PULL_INTERVAL. Unlike it - this one is responsible to detect whether the
    # subscription should be included in the subscriptions list to query next chunk of events. Thus, this setting only
    # determines whether it is time to make a request, but how frequent would be the actual request - determines
    # SubscriptionFeeder::EVENTS_PULL_INTERVAL.
    # @see PgEventstore::SubscriptionFeeder::EVENTS_PULL_INTERVAL
    # @return [Float]
    MIN_EVENTS_PULL_INTERVAL = 0.2
    private_constant :MIN_EVENTS_PULL_INTERVAL

    # @return [Time]
    DEFAULT_TIMESTAMP = Time.at(0).utc.freeze

    # @!attribute id
    #   @return [Integer, nil]
    attribute(:id)
    # @!attribute set
    #   @return [String, nil] Subscription's set. Subscription should have unique pair of set and name.
    attribute(:set)
    # @!attribute name
    #   @return [String, nil] Subscription's name. Subscription should have unique pair of set and name.
    attribute(:name)
    # @!attribute total_processed_events
    #   @return [Integer, nil] total number of events, processed by this subscription
    attribute(:total_processed_events)
    # @!attribute options
    #   @return [Hash, nil] subscription's options to be used to query events. See {SubscriptionManager#subscribe} for
    #     the list of available options
    attribute(:options)
    # @!attribute current_position
    #   @return [Integer, nil] current Subscription's position. It is updated automatically each time an event is
    #     processed
    attribute(:current_position)
    # @!attribute state
    #   @return [String, nil] current Subscription's state. It is updated automatically during Subscription's life cycle
    #     See {RunnerState::STATES} for possible values.
    attribute(:state)
    # @!attribute average_event_processing_time
    #   @return [Float, nil] a speed of the subscription. Divide 1 by this value to determine how much events are
    #     processed by the Subscription per second.
    attribute(:average_event_processing_time)
    # @!attribute restart_count
    #   @return [Integer, nil] the number of Subscription's restarts after its failure
    attribute(:restart_count)
    # @!attribute max_restarts_number
    #   @return [Integer, nil] maximum number of times the Subscription can be restarted
    attribute(:max_restarts_number)
    # @!attribute time_between_restarts
    #   @return [Integer, nil] interval in seconds between retries of failed Subscription
    attribute(:time_between_restarts)
    # @!attribute last_restarted_at
    #   @return [Time, nil] last time the Subscription was restarted
    attribute(:last_restarted_at)
    # @!attribute last_error
    #   @return [Hash, nil] the information about
    #     last error caused when processing events by the Subscription.
    attribute(:last_error)
    # @!attribute last_error_occurred_at
    #   @return [Time, nil] the time when the last error occurred
    attribute(:last_error_occurred_at)
    # @!attribute chunk_query_interval
    #   @return [Integer, Float, nil] determines how often to pull events for the given Subscription in seconds
    attribute(:chunk_query_interval)
    # @!attribute last_chunk_fed_at
    #   @return [Time, nil] shows the time when last time events were fed to the event's processor
    attribute(:last_chunk_fed_at)
    # @!attribute last_chunk_greatest_position
    #   @return [Integer, nil] shows the greatest global_position of the last event in the last chunk fed to the event's
    #     processor
    attribute(:last_chunk_greatest_position)
    # @!attribute locked_by
    #   @return [Integer, nil] The id of subscription manager which obtained the lock of the Subscription. _nil_ value
    #     means that the Subscription isn't locked yet by any subscription manager.
    attribute(:locked_by)
    # @!attribute created_at
    #   @return [Time, nil]
    attribute(:created_at)
    # @!attribute updated_at
    #   @return [Time, nil]
    attribute(:updated_at)

    class << self
      # @param subscriptions_set_id [Integer] SubscriptionsSet#id
      # @param subscriptions [Array<PgEventstore::Subscription>]
      # @return [void]
      def ping_all(subscriptions_set_id, subscriptions)
        result = subscription_queries.ping_all(subscriptions_set_id, subscriptions.map(&:id))
        subscriptions.each do |subscription|
          next unless result[subscription.id]

          subscription.assign_attributes(updated_at: result[subscription.id])
        end
      end

      # @return [PgEventstore::SubscriptionQueries]
      def subscription_queries
        SubscriptionQueries.new(connection)
      end
    end

    def options=(val)
      @options = Utils.deep_transform_keys(val, &:to_sym)
    end

    # @param attrs [Hash]
    # @return [Hash]
    def update(attrs)
      assign_attributes(subscription_queries.update(id, attrs:, locked_by:))
    end

    # @param attrs [Hash]
    # @return [Hash]
    def assign_attributes(attrs)
      attrs.each do |attr, value|
        public_send("#{attr}=", value)
      end
    end

    # Locks the Subscription by the given lock id
    # @param lock_id [Integer] SubscriptionsSet#id
    # @param force [Boolean]
    # @return [PgEventstore::Subscription]
    def lock!(lock_id, force: false)
      self.id = subscription_queries.find_or_create_by(set:, name:)[:id]
      self.locked_by = subscription_queries.lock!(id, lock_id, force:)
      reset_runtime_attributes
      self
    end

    # Dup the current object without assigned connection
    # @return [PgEventstore::Subscription]
    def dup
      Subscription.new(**Utils.deep_dup(options_hash))
    end

    # @return [PgEventstore::Subscription]
    def reload
      assign_attributes(subscription_queries.find!(id))
      self
    end

    # @return [Integer]
    def hash
      id.hash
    end

    # @param other [Object]
    # @return [Boolean]
    def eql?(other)
      return false unless other.is_a?(Subscription)

      hash == other.hash
    end

    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(Subscription)

      id == other.id
    end

    private

    # @return [void]
    def reset_runtime_attributes
      update(
        options:,
        restart_count: 0,
        last_restarted_at: nil,
        max_restarts_number:,
        chunk_query_interval: [chunk_query_interval, MIN_EVENTS_PULL_INTERVAL].max,
        last_chunk_fed_at: DEFAULT_TIMESTAMP,
        last_chunk_greatest_position: nil,
        last_error: nil,
        last_error_occurred_at: nil,
        time_between_restarts:,
        state: RunnerState::STATES[:initial]
      )
    end

    # @return [PgEventstore::SubscriptionQueries]
    def subscription_queries
      self.class.subscription_queries
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  module EventsProcessorConsumer
    class << self
      def consumer_class(in_batches)
        return Multiple if in_batches

        Single
      end

      def included(othermod)
        othermod.extend(ClassMethods)
        super
      end
    end

    module ClassMethods
      def create_consumer(handler, deserializer)
        raise NotImplementedError
      end
    end

    # @param callbacks [PgEventstore::Callbacks]
    # @param raw_events [Array<Hash>]
    # @param raw_events_cond [MonitorMixin::ConditionVariable]
    # @return [void]
    def call(callbacks, raw_events, raw_events_cond)
      raise NotImplementedError
    end
  end
end

require_relative 'events_processor_consumer/single'
require_relative 'events_processor_consumer/multiple'

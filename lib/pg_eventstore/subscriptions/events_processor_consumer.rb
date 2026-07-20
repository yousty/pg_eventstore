# frozen_string_literal: true

module PgEventstore
  # @!visibility private
  module EventsProcessorConsumer
    class << self
      # @param in_batches [Boolean]
      # @return [Class]
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
    # @param repository [PgEventstore::Chunks::Repository]
    # @param repository_cond [MonitorMixin::ConditionVariable]
    # @return [void]
    def call(callbacks, repository, repository_cond)
      raise NotImplementedError
    end

    # @return [void]
    def clear_unprocessed_events
      raise NotImplementedError
    end
  end
end

require_relative 'events_processor_consumer/single'
require_relative 'events_processor_consumer/multiple'
require_relative 'events_processor_consumer/replica'

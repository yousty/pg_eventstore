# frozen_string_literal: true

require 'benchmark'

module PgEventstore
  # This class measures the performance of Subscription's handler and returns the average time required to process an
  # event.
  # @!visibility private
  class SubscriptionHandlerPerformance
    extend Forwardable

    # @return [Integer] the number of measurements to keep
    TIMINGS_TO_KEEP = 100

    def_delegators :@lock, :synchronize

    def initialize
      @lock = Thread::Mutex.new
      @timings = []
    end

    # Yields the given block to measure its execution time
    # @return [Object] the result of yielded block
    def track_exec_time
      result = nil
      time = Benchmark.realtime { result = yield }
      synchronize do
        @timings.shift if @timings.size == TIMINGS_TO_KEEP
        @timings.push(time)
      end
      result
    end

    # The average time required to process an event.
    # @return [Float]
    def average_event_processing_time
      synchronize { @timings.size.zero? ? 0.0 : @timings.sum / @timings.size }
    end
  end
end

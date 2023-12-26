# frozen_string_literal: true

require 'benchmark'

module PgEventstore
  # @!visibility private
  class SubscriptionStats
    extend Forwardable

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
        @timings.unshift if @timings.size == TIMINGS_TO_KEEP
        @timings.push(time)
      end
      result
    end

    def events_processing_frequency
      synchronize { @timings.size.zero? ? 0 : @timings.sum / @timings.size }
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  class AsyncQueryRunner
    def initialize
      @jobs = {}
    end

    # @return [Integer]
    def jobs_size
      @jobs.size
    end

    # @return [void]
    def run
      loop do
        break if @jobs.empty?

        run_once
      end
    end

    # rubocop:disable Style/HashEachMethods
    def run_once
      return if @jobs.empty?

      @jobs.keys.each do |job|
        job.resume
        @jobs.delete(job) unless job.alive?
      end
    end
    # rubocop:enable Style/HashEachMethods

    # @return [void]
    def async(&)
      @jobs[Fiber.new(&)] = true
    end
  end
end

# frozen_string_literal: true

module PgEventstore
  class AsyncQueryRunner
    def initialize
      @jobs = {}
    end

    def jobs_size
      @jobs.size
    end

    def run
      loop do
        break if @jobs.empty?

        run_once
      end
    end

    def run_once
      return if @jobs.empty?

      @jobs.keys.each do |job|
        job.resume
        @jobs.delete(job) unless job.alive?
      end
    end

    def async(&)
      @jobs[Fiber.new(&)] = true
    end
  end
end

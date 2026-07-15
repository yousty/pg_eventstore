# frozen_string_literal: true

module PgEventstore
  class AsyncRunner
    class Cancellation < StandardError
    end

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

    def run_once
      return if @jobs.empty?

      @jobs.keys.each do |job|
        @jobs[job] = true
        job.resume
        @jobs.delete(job) unless job.alive?
      end
    rescue
      @jobs.each do |job, started|
        next unless job.alive?

        if started
          begin
            job.raise(Cancellation)
          rescue StandardError
            # Because the rescue mechanisms inside the terminating job can potentially raise - catch them here
          end
        end

        begin
          # Kill those jobs which survived our Cancellation exception
          job.kill if job.alive?
        rescue StandardError
          # Ensure we handle any errors inside an exception handler(e.g. ensure block) of the given job
        end
      end

      @jobs.clear
      raise
    end

    # @return [void]
    def async(&)
      @jobs[Fiber.new(&)] = false
    end
  end
end

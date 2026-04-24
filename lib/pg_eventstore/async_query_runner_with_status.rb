# frozen_string_literal: true

module PgEventstore
  class AsyncQueryRunnerWithStatus
    def initialize(ready_status)
      @jobs = {}
      @ready_status = ready_status
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

      prev_jobs_are_ready = true
      ready_jobs = {}
      @jobs.keys.each do |job|
        @jobs[job] = job.resume unless @jobs[job] == @ready_status
        if prev_jobs_are_ready && @jobs[job] == @ready_status
          ready_jobs[job] = true
        else
          prev_jobs_are_ready = false
        end

        @jobs.delete(job) unless job.alive?
      end

      ready_jobs.each_key do |job|
        job.resume
        raise "The job was marked as ready to calculate final result, but it was interrupted one more time. Not continuing further." if job.alive?

        @jobs.delete(job)
      end
    end

    def async(&)
      @jobs[Fiber.new(&)] = nil
    end
  end
end

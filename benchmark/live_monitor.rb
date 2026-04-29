# frozen_string_literal: true

class LiveMonitor
  def initialize(connection)
    @connection = connection
    @total = 0
    @per_second = 0
    @per_minute = 0
  end

  def start
    track_per_minute
    track_per_second
    output_async
  end

  def stop
    @total = 0
    @per_second = 0
    @per_minute = 0
    @track_per_second_t&.exit
    @track_per_minute_t&.exit
    @output_t&.exit
  end

  private

  def output_async
    @output_t = Thread.new do
      loop do
        sleep 2
        print "Current performance: #{@per_second}/s #{@per_minute}/min           \r"
      end
    end
  end

  def track_per_second
    @track_per_second_t = Thread.new do
      count_was = @connection.with { |c| c.exec('select count(*) from events_global_index').first['count'] }

      loop do
        sleep 1
        count_now = @connection.with { |c| c.exec('select count(*) from events_global_index').first['count'] }

        @per_second = count_now - count_was
        count_was = count_now
      end
    end
  end

  def track_per_minute
    @track_per_minute_t = Thread.new do
      count_was = @connection.with { |c| c.exec('select count(*) from events_global_index').first['count'] }

      loop do
        sleep 60
        count_now = @connection.with { |c| c.exec('select count(*) from events_global_index').first['count'] }

        @per_minute = count_now - count_was
        count_was = count_now
      end
    end
  end
end

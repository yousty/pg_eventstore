# frozen_string_literal: true

require 'pg_eventstore'
require 'securerandom'
require_relative 'stats'

class Benchmarks
  APPENDS_PER_PROCESS = 10_000
  SINGLE_STREAM_APPENDS_PER_PROCESS = 1_000

  # This config results in 11520 event partitions and 11673 partitions in total. This allows to see how well current
  # implementation scales with the number of partitions
  EVENT_TYPES = %w[Foo Bar Baz Lorem Ipsum Dolor Sit Amet].flat_map do |e|
    10.times.map { |t| "#{e}-#{t}" }
  end.freeze
  CONTEXTS = %w[SomeContext AnotherContext FooCtx Ctx BarCtx BazCtx BazBarCtx FooBarCtx FooBazCtx]
  STREAM_NAMES = %w[User Post Article Comment Reaction Chapter UserProfile Book].flat_map do |s|
    2.times.map { |t| "#{s}-#{t}" }
  end.freeze

  class << self
    # Populate db with some data, so that tests are performed over non-empty db
    def warm_up
      puts "Concurrency is: #{CONCURRENCY}. Warming up..."
      lock = Thread::Mutex.new
      to_append = 0
      workers = CONCURRENCY.times.map do
        Thread.new do
          # [{ stream: stream1, events: [event1, event2, ...] }, ...]
          Thread.current[:jobs] = []
          loop do
            job = Thread.current[:jobs].shift
            unless job
              sleep 0.5
              next
            end
            PgEventstore.client.append_to_stream(job[:stream], job[:events])
            lock.synchronize { to_append -= job[:events].size }
          end
        end
      end
      loop do
        break if workers.all? { |worker| worker[:jobs]&.empty? && worker.status == 'sleep' }
      end
      CONTEXTS.each_with_index do |context, i|
        STREAM_NAMES.each_with_index do |stream_name, j|
          stream = PgEventstore::Stream.new(
            context:,
            stream_name:,
            stream_id: SecureRandom.uuid_v7
          )
          events = 1000.times.map do |event_num|
            PgEventstore::Event.new(data: { foo: "foo-#{event_num}" }, type: EVENT_TYPES[event_num % EVENT_TYPES.size])
          end
          lock.synchronize { to_append += events.size }
          worker = workers[(i + j) % workers.size]
          worker[:jobs].push({ stream:, events: })
        end
      end
      loop do
        break if lock.synchronize { to_append == 0 }
        sleep 1
      end
      workers.each(&:exit)
      puts "Done warming up. Benchmarking now..."
    end
  end

  attr_reader :stats

  # @param parallel_num [Integer] number of parallel processes
  def initialize(parallel_num)
    @parallel_num = parallel_num
    @stats = Stats.new
  end

  # @param method_name [String, Symbol]
  # @return [void]
  def in_processes(method_name)
    puts "Running #{@parallel_num} processes to benchmark #{method_name.inspect} performance"
    PgEventstore.connection.shutdown
    pids = @parallel_num.times.map do
      fork do
        public_send(method_name)
        @stats.persist_stats
      end
    end
    PgEventstore.connection.establish_connection
    pids.each { |pid| Process.waitpid(pid) }
  end

  def append_events_to_different_streams
    append_events(__method__, stream_id: "#{__method__}-#{Process.pid}")
  end

  def append_events_to_single_stream
    append_events(
      __method__,
      stream_id: __method__.to_s,
      appends: SINGLE_STREAM_APPENDS_PER_PROCESS,
    )
  end

  def append_events_with_markers_to_different_streams
    append_events(
      __method__,
      stream_id: "#{__method__}-#{Process.pid}",
      generate_random_marker: true,
    )
  end

  def append_events_with_markers_to_single_stream
    append_events(
      __method__,
      stream_id: __method__.to_s,
      appends: SINGLE_STREAM_APPENDS_PER_PROCESS,
      generate_random_marker: true,
    )
  end

  private

  # @param method_name [String, Symbol]
  # @param stream_id [String]
  # @param appends [Integer]
  # @param generate_random_marker [Boolean]
  # @return [void]
  def append_events(method_name, stream_id:, appends: APPENDS_PER_PROCESS, generate_random_marker: false)
    stream = PgEventstore::Stream.new(
      context: CONTEXTS.first,
      stream_name: STREAM_NAMES.first,
      stream_id:
    )
    appends.times do |event_num|
      markers = generate_random_marker ? [SecureRandom.uuid_v7] : []
      event = PgEventstore::Event.new(
        data: { foo: :bar, id: event_num },
        type: EVENT_TYPES[event_num % EVENT_TYPES.size],
        markers:
      )
      benchmark(method_name) { PgEventstore.client.append_to_stream(stream, event) }
    end
  end

  # @param method_name [String, Symbol]
  # @return [void]
  def benchmark(method_name, &)
    time = PgEventstore::Utils.benchmark(&)
    @stats.update(method_name, time)
  end
end

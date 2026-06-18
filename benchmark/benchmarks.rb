# frozen_string_literal: true

require 'pg_eventstore'
require 'securerandom'
require_relative 'stats'

class Benchmarks
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

  # @param parallel_num [Integer] number of parallel threads/processes
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
        public_send(method_name, :processes)
        @stats.persist_stats
      end
    end
    PgEventstore.connection.establish_connection
    pids.each { |pid| Process.waitpid(pid) }
  end

  # @param method_name [String, Symbol]
  # @return [void]
  def in_threads(method_name)
    puts "Running #{@parallel_num} threads to benchmark #{method_name.inspect} performance"
    threads = @parallel_num.times.map do
      Thread.new do
        public_send(method_name, :threads)
      end
    end
    threads.each(&:join)
    @stats.persist_stats
  end

  def frequent_streams_writes(concurrent_method = nil)
    1_000.times do |i|
      stream = PgEventstore::Stream.new(
        context: CONTEXTS[i % CONTEXTS.size],
        stream_name: STREAM_NAMES[i % STREAM_NAMES.size],
        stream_id: "#{Process.pid}-#{Thread.current.__id__}-#{i}"
      )
      10.times.each do |j|
        event = PgEventstore::Event.new(data: { foo: :bar, id: "#{i}-#{j}" }, type: EVENT_TYPES[j % EVENT_TYPES.size])
        benchmark(__method__, concurrent_method) { PgEventstore.client.append_to_stream(stream, event) }
      end
    end
  end

  def frequent_events_writes(concurrent_method = nil)
    10.times do |i|
      stream = PgEventstore::Stream.new(
        context: CONTEXTS[i % CONTEXTS.size],
        stream_name: STREAM_NAMES[i % STREAM_NAMES.size],
        stream_id: "#{Process.pid}-#{Thread.current.__id__}-#{i}"
      )
      1_000.times.each do |j|
        event = PgEventstore::Event.new(data: { foo: :bar, id: "#{i}-#{j}" }, type: EVENT_TYPES[j % EVENT_TYPES.size])
        benchmark(__method__, concurrent_method) { PgEventstore.client.append_to_stream(stream, event) }
      end
    end
  end

  private

  # @param method_name [String, Symbol]
  # @return [void]
  def benchmark(method_name, concurrent_method, &blk)
    time = PgEventstore::Utils.benchmark(&blk)
    @stats.update("#{method_name}_#{concurrent_method}", time)
  end
end

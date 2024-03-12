# frozen_string_literal: true

require 'pg_eventstore'
require 'benchmark'
require 'securerandom'
require_relative 'stats'

class Benchmarks
  EVENT_TYPES = %w[Foo Bar Baz Lorem Ipsum Dolor Sit Amet].freeze
  CONTEXTS = %w[SomeContext AnotherContext FooCtx Ctx BarCtx BazCtx BazBarCtx FooBarCtx FooBazCtx].freeze
  STREAM_NAMES = %w[User Post Article Comment Reaction Chapter UserProfile Book].freeze

  class << self
    # Populate db with some data, so that tests are performed over non-empty db
    def warm_up
      puts "Warming up..."
      CONTEXTS.each do |context|
        STREAM_NAMES.each do |stream_name|
          stream = PgEventstore::Stream.new(
            context: context,
            stream_name: stream_name,
            stream_id: SecureRandom.uuid
          )
          events = 1000.times.map do |j|
            PgEventstore::Event.new(data: { foo: "foo-#{j}" }, type: EVENT_TYPES.sample)
          end
          PgEventstore.client.append_to_stream(stream, events)
        end
      end
    end
  end

  attr_reader :stats

  # @param parallel_num [Integer] number of parallel threads/processes
  # @param stats [Stats]
  def initialize(parallel_num)
    @parallel_num = parallel_num
    @stats = Stats.new
  end

  # @param method_name [String, Symbol]
  # @return [void]
  def in_processes(method_name)
    puts "Running #{@parallel_num} processes to benchmark #{method_name.inspect} performance"
    pids = @parallel_num.times.map do
      fork do
        public_send(method_name, :processes)
        @stats.persist_stats
      end
    end
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
    time = Benchmark.realtime(&blk)
    @stats.update("#{method_name}_#{concurrent_method}", time)
  end
end

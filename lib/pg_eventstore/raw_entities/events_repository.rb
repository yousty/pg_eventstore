# frozen_string_literal: true

module PgEventstore
  module RawEntities
    class EventsRepository
      include MonitorMixin

      def initialize(...)
        super
        @chunks = SynchronizedArray.new
      end

      def add_chunk(chunk, condition: nil)
        mon_try_enter
        @chunks.push(chunk)
        condition&.broadcast if mon_owned?
      ensure
        mon_exit if mon_owned?
      end

      def clear
        @chunks.clear
      end

      def size
        @chunks.sum(&:size)
      end

      def empty?
        @chunks.empty?
      end

      # Consumes all chunks and returns enumerator holding them.
      # @return [Enumerator]
      def consume_all
        synchronize do
          chunks = @chunks.slice!(0..)
          Enumerator.new do |y|
            chunks.each do |chunk|
              loop do
                chunk.take(nil).each(&y.method(:<<))
                break if chunk.empty?
              end
            end
          end
        end
      end

      # @param events_num [Integer, nil]
      # @param timeout [Float, Integer]
      # @param condition [MonitorMixin::ConditionVariable]
      # @return [Array<Hash>]
      def wait_and_consume(events_num:, timeout:, condition:)
        synchronize do
          condition.wait(timeout) if @chunks.empty?
          return [] if @chunks.empty?

          chunk = @chunks.at(0)
          chunk.take(events_num).tap do
            @chunks.delete(chunk) if chunk.empty?
          end
        end
      end
    end
  end
end

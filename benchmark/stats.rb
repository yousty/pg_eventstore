# frozen_string_literal: true

require 'json'
require 'connection_pool'
require 'redis'
require 'etc'

class Stats
  BM_STATS_NAMESPACE = 'pg_evetstore-stats'

  class << self
    def redis
      @redis ||= ConnectionPool.new(size: Etc.nprocessors) { Redis.new(host: 'localhost', port: '6579', db: 1) }
    end

    def stats
      redis.with do |conn|
        keys = conn.keys
        keys.group_by { |k| k.split(':')[1] }.map do |stat_name, stat_keys|
          stats = stat_keys.each.with_object({ min: 0, max: 0, avg: 0 }) do |key, res|
            stats = JSON.parse(conn.get(key), symbolize_names: true)
            res[:min] += stats[:min].to_f / keys.size
            res[:max] += stats[:max].to_f / keys.size
            res[:avg] += stats[:total].to_f / stats[:count] / keys.size
          end
          [stat_name.to_sym, stats]
        end.sort_by(&:first).to_h
      end
    end
  end

  def initialize
    @redis = self.class.redis
    @stats = {}
  end

  # @param bm_name [String, Symbol]
  # @param time [Float] seconds
  # @return [void]
  def update(bm_name, time)
    key = bm_key(bm_name)
    @stats[key] ||= { min: 1_000, max: 0, count: 0, total: 0 }
    @stats[key][:min] = [@stats[key][:min], time].min
    @stats[key][:max] = [@stats[key][:max], time].max
    @stats[key][:count] += 1
    @stats[key][:total] += time
  end

  # @return [void]
  def persist_stats
    @stats.each do |key, result|
      @redis.with do |conn|
        conn.set(key, result.to_json)
      end
    end
  end

  private

  # @param bm_name [String, Symbol]
  # @return [String]
  def bm_key(bm_name)
    "#{BM_STATS_NAMESPACE}:#{bm_name}:#{Process.pid}-#{Thread.current.__id__}"
  end
end

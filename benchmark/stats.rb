# frozen_string_literal: true

require 'json'
require 'fileutils'

class Stats
  BM_STATS_NAMESPACE = 'pg_evetstore-bm'

  class Repo
    def initialize
      @dir = File.expand_path("tmp/#{BM_STATS_NAMESPACE}")
    end

    def reset
      FileUtils.rm_rf(@dir)
      FileUtils.mkdir_p(@dir)
    end

    def add(key, content)
      Dir.chdir(@dir) do
        file = File.new("#{key}.txt", "w")
        file.write(content)
        file.close
      end
    end

    def stats
      Dir["#{@dir}/*.txt"].each.with_object({}) do |file_name, res|
        stat = File.basename(file_name).sub('.txt', '').split('-')[0]
        res[stat.to_sym] ||= []
        res[stat.to_sym].push(*JSON.parse(File.read(file_name), symbolize_names: true))
      end
    end
  end

  class << self
    def repo
      @repo ||= Repo.new
    end

    def stats
      repo.stats.to_h do |stat_name, timings|
        timings = timings.sort
        p95_timings = timings[..((timings.size * 0.95).round)]
        p99_timings = timings[..((timings.size * 0.99).round)]
        stats = {
          min: timings.min,
          max: timings.max,
          p95: p95_timings.max,
          p99: p99_timings.max,
          p95_avg: p95_timings.sum / p95_timings.size.to_f,
          p99_avg: p99_timings.sum / p99_timings.size.to_f,
        }
        [stat_name, stats]
      end
    end
  end

  def initialize
    @stats = {}
  end

  # @param bm_name [String, Symbol]
  # @param time [Float] seconds
  # @return [void]
  def update(bm_name, time)
    key = bm_key(bm_name)
    @stats[key] ||= []
    @stats[key].push(time)
  end

  # @return [void]
  def persist_stats
    @stats.each do |key, result|
      self.class.repo.add(key, result.to_json)
    end
  end

  private

  # @param bm_name [String, Symbol]
  # @return [String]
  def bm_key(bm_name)
    "#{bm_name}-#{Process.pid}-#{Thread.current.__id__}"
  end
end

# frozen_string_literal: true

require 'monitor'

module PgEventstore
  # @!visibility private
  class SynchronizedArray < Array
    include MonitorMixin

    alias old_shift shift
    alias old_unshift unshift
    alias old_push push
    alias old_clear clear
    alias old_size size
    alias old_empty? empty?

    def shift(...)
      synchronize { old_shift(...) }
    end

    def unshift(...)
      synchronize { old_unshift(...) }
    end

    def push(...)
      synchronize { old_push(...) }
    end

    def clear(...)
      synchronize { old_clear(...) }
    end

    def size(...)
      synchronize { old_size(...) }
    end

    def empty?(...)
      synchronize { old_empty?(...) }
    end
  end
end

# frozen_string_literal: true

class DeferredValue
  class << self
    def get_dv(obj)
      @lock.synchronize do
        @deferred_objects[obj] ||= new(obj)
      end
    end

    def teardown
      @deferred_objects.clear
    end

    private

    def init_vars
      @deferred_objects = {}.compare_by_identity
      @lock = Thread::Mutex.new
    end
  end
  init_vars

  def initialize(obj)
    @object = obj
    reset
  end

  def deferred_wait(timeout: 0, &)
    if @first_access
      wait_async(timeout:, &)
      @first_access = false
      @object
    else
      @async_job&.join
      @object.tap do
        reset
      end
    end
  end

  def wait_until(...)
    deferred_wait(...)
    deferred_wait(...)
  end

  protected

  def reset
    @first_access = true
    @async_job = nil
  end

  private

  def wait_async(timeout:, &blk)
    @async_job = Thread.new do
      start_time = Timecop.return { Time.now.utc }
      Kernel.loop do
        sleep 0.1
        break if Timecop.return { Time.now.utc } - start_time > timeout
        break if blk.call(@object)
      end
    end
  end
end

module DeferredValueExt
  def dv(*args)
    puts 'More than one argument in #dv is ignored!' if args.size > 1
    obj = args.empty? ? Object.new : args.first
    DeferredValue.get_dv(obj)
  end
end

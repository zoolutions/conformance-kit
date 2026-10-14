# frozen_string_literal: true

module Fixtures
  # VIOLATING: an unguarded `@cache ||=`. The miss path holds the race window
  # open until `arrivals` threads have all missed, so the race is forced, not
  # hoped for: every thread builds its own Hash.
  class RacyCache
    WINDOW_TIMEOUT = 5

    def initialize(arrivals:)
      @arrivals = arrivals
      @arrived = 0
      @lock = Mutex.new
      @all_in = ConditionVariable.new
    end

    def cache
      @cache ||= begin
        hold_window_open
        {}
      end
    end

    private

    def hold_window_open
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WINDOW_TIMEOUT
      @lock.synchronize do
        @arrived += 1
        @all_in.broadcast
        while @arrived < @arrivals
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if remaining <= 0

          @all_in.wait(@lock, remaining)
        end
      end
    end
  end

  # CONFORMING: the same cache, built under a lock.
  class LockedCache
    def initialize
      @lock = Mutex.new
    end

    def cache
      @lock.synchronize { @cache ||= {} }
    end
  end
end

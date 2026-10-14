# frozen_string_literal: true

require "conformance_kit"

module ConformanceKit
  # The Minitest front end: the same four checks as assertions.
  #
  #   class CacheTest < Minitest::Test
  #     include ConformanceKit::Minitest
  #
  #     def test_cache_is_thread_safe
  #       assert_thread_safe(threads: 8, iterations: 50, consistent: :identical) { MyGem.cache_for(:key) }
  #     end
  #   end
  #
  # Uses only `assert` and `skip`, so it works on Minitest 5 and 6.
  module Minitest
    def assert_thread_safe(threads: 8, iterations: 50, consistent: nil, &)
      conformance_enforce(Checks::ThreadContention.call(
                            threads: threads, iterations: iterations, consistent: consistent, &
                          ))
    end

    def assert_fiber_safe(fibers: 8, iterations: 50, consistent: nil, &)
      conformance_enforce(Checks::FiberReactor.call(fibers: fibers, iterations: iterations, consistent: consistent, &))
    end

    def assert_boot_finalized(readers:, finalize: nil)
      conformance_enforce(Checks::BootFinalized.call(readers: readers, finalize: finalize))
    end

    def assert_runs_in_ractor(inputs: [], &)
      conformance_enforce(Checks::RactorCanary.call(inputs: inputs, &))
    end

    private

    def conformance_enforce(result)
      skip(result.message) if result.skipped?
      assert(result.passed?, result.message)
    end
  end
end

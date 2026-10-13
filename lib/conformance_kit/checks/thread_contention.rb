# frozen_string_literal: true

module ConformanceKit
  module Checks
    # "thread-safe under contention": `threads` threads released together, each
    # making `iterations` calls. Fails on any exception, or when the results
    # disagree under `consistent:`.
    module ThreadContention
      NAME = "thread-safe under contention"

      class << self
        def call(threads: 8, iterations: 50, consistent: nil, &subject)
          Consistency.validate!(consistent)
          outcomes = run(threads, iterations, subject)
          errors = outcomes.grep(Exception)
          return Result.fail("#{NAME}: #{Consistency.raised(errors, threads, 'threads')}") if errors.any?

          problem = Consistency.problem(outcomes.flatten(1), consistent)
          problem ? Result.fail("#{NAME}: #{threads} threads × #{iterations} calls #{problem}") : Result.pass
        end

        private

        def run(threads, iterations, subject)
          start = Queue.new
          workers = Array.new(threads) do
            Thread.new do # rubocop:disable ThreadSafety/NewThread -- contention is the point of the check
              start.pop
              Array.new(iterations) { subject.call }
            rescue StandardError => e
              e
            end
          end
          threads.times { start << true }
          workers.map(&:value)
        end
      end
    end
  end
end

# frozen_string_literal: true

module ConformanceKit
  module Checks
    # "fiber-safe under an Async reactor": `fibers` Async tasks, each making
    # `iterations` calls. Needs the `async` gem, which is never a dependency of
    # the kit: skipped with a reason when it cannot be loaded.
    module FiberReactor
      NAME = "fiber-safe under an Async reactor"
      LOAD_ASYNC = -> { require "async" }

      class << self
        def call(fibers: 8, iterations: 50, consistent: nil, loader: LOAD_ASYNC, &subject)
          Consistency.validate!(consistent)
          begin
            loader.call
          rescue LoadError => e
            return Result.skip("#{NAME} needs the async gem, which is not loadable (#{e.message}): " \
                               "add `gem \"async\"` to the Gemfile's test group to run it")
          end

          verdict(run(fibers, iterations, subject), fibers, iterations, consistent)
        end

        private

        def run(fibers, iterations, subject)
          Async do |task|
            tasks = Array.new(fibers) do
              task.async do
                Array.new(iterations) { subject.call }
              rescue StandardError => e
                e
              end
            end
            tasks.map(&:wait)
          end.wait
        end

        def verdict(outcomes, fibers, iterations, consistent)
          errors = outcomes.grep(Exception)
          return Result.fail("#{NAME}: #{Consistency.raised(errors, fibers, 'fibers')}") if errors.any?

          problem = Consistency.problem(outcomes.flatten(1), consistent)
          problem ? Result.fail("#{NAME}: #{fibers} fibers × #{iterations} calls #{problem}") : Result.pass
        end
      end
    end
  end
end

# frozen_string_literal: true

module ConformanceKit
  module Checks
    # The outcome reporting shared by the thread and fiber checks: exceptions,
    # and the `consistent:` option.
    module Consistency
      MODES = %i[identical equal].freeze
      # How many distinct results a failure report tells apart before it stops counting.
      DIAGNOSED = 10

      class << self
        def validate_counts!(**counts)
          counts.each do |name, count|
            next if count.is_a?(Integer) && count.positive?

            raise ArgumentError, "#{name}: must be a positive Integer (got #{count.inspect}); " \
                                 "zero would pass without a single call"
          end
        end

        def validate!(consistent)
          return if consistent.nil? || consistent.respond_to?(:call) || MODES.include?(consistent)

          raise ArgumentError, "consistent: must be :identical, :equal or a callable taking every result, " \
                               "got #{consistent.inspect}"
        end

        # nil when consistent, a failure description otherwise.
        def problem(results, consistent)
          case consistent
          when nil then nil
          when :identical then distinct(results.uniq(&:__id__), consistent)
          when :equal then distinct(uniq_by_equality(results), consistent)
          else "the `consistent:` check returned false for #{results.size} results" unless consistent.call(results)
          end
        end

        def raised(errors, total, unit)
          first = errors.first
          where = first.backtrace ? " (#{first.backtrace.first})" : ""
          "#{errors.size} of #{total} #{unit} raised; first: #{first.class}: #{first.message}#{where}"
        end

        private

        # Array#uniq compares with eql?/hash (1 and 1.0 differ); :equal promises ==. Stops past
        # DIAGNOSED distinct values, so N different results cost O(N) == calls, not O(N²).
        def uniq_by_equality(results)
          results.each_with_object([]) do |result, seen|
            next if seen.any? { |s| s == result }

            seen << result
            break seen if seen.size > DIAGNOSED
          end
        end

        def distinct(unique, mode)
          return nil if unique.size <= 1

          count = unique.size > DIAGNOSED ? "more than #{DIAGNOSED}" : unique.size
          classes = unique.group_by { _1.class.name }.map { |name, all| "#{name} ×#{all.size}" }.join(", ")
          "returned #{count} distinct results (#{classes}), so the `consistent: #{mode.inspect}` check failed"
        end
      end
    end
  end
end

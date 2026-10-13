# frozen_string_literal: true

module ConformanceKit
  module Checks
    # The outcome reporting shared by the thread and fiber checks: exceptions,
    # and the `consistent:` option.
    module Consistency
      MODES = %i[identical equal].freeze

      class << self
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
          when :equal then distinct(results.uniq, consistent)
          else "the `consistent:` check returned false for #{results.size} results" unless consistent.call(results)
          end
        end

        def raised(errors, total, unit)
          first = errors.first
          where = first.backtrace ? " (#{first.backtrace.first})" : ""
          "#{errors.size} of #{total} #{unit} raised; first: #{first.class}: #{first.message}#{where}"
        end

        private

        def distinct(unique, mode)
          return nil if unique.size <= 1

          classes = unique.group_by { _1.class.name }.map { |name, all| "#{name} ×#{all.size}" }.join(", ")
          "returned #{unique.size} distinct results (#{classes}), so the `consistent: #{mode.inspect}` check failed"
        end
      end
    end
  end
end

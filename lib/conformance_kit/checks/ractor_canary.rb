# frozen_string_literal: true

module ConformanceKit
  module Checks
    # "runs inside a non-main Ractor": runs a capture-free block on the main
    # Ractor and inside `Ractor.new(*inputs)`, and compares the two results.
    # Ruby 4.0+ only (`Ractor#value`); skipped with a reason below.
    module RactorCanary
      NAME = "runs inside a non-main Ractor"

      class << self
        def call(inputs: [], &block)
          return Result.skip(unavailable) unless available?

          expected = block.call(*inputs)
          actual = ::Ractor.new(*inputs, &block).value
          return Result.pass if actual == expected

          Result.fail("#{NAME}: returned #{actual.inspect} inside the Ractor " \
                      "but #{expected.inspect} on the main Ractor")
        rescue ::Ractor::RemoteError => e
          cause = e.cause || e
          Result.fail("#{NAME}: raised #{cause.class} inside the Ractor: #{cause.message}")
        rescue ::Ractor::IsolationError, ::ArgumentError => e
          raise unless e.message.include?("isolate")

          Result.fail("#{NAME}: the block must be capture-free (pass values through inputs:): #{e.message}")
        end

        private

        def available? = defined?(::Ractor) && ::Ractor.method_defined?(:value)

        def unavailable
          "#{NAME} needs Ruby 4.0+ (Ractor#value); running #{RUBY_ENGINE} #{RUBY_VERSION}"
        end
      end
    end
  end
end

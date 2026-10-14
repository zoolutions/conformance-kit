# frozen_string_literal: true

require "rspec/core"
require "conformance_kit"

module ConformanceKit
  # The RSpec front end: `require "conformance_kit/rspec"` registers four shared
  # examples. Each example group defines `subject_call`, a callable for the
  # operation under test (not needed by "a boot-finalized configuration").
  #
  #   let(:subject_call) { -> { MyGem.cache_for(:key) } }
  #   it_behaves_like "thread-safe under contention", threads: 8, iterations: 50, consistent: :identical
  module RSpec
    class << self
      def register!
        register_thread_example
        register_fiber_example
        register_boot_example
        register_ractor_example
      end

      def enforce(example, result)
        return if result.passed?
        return example.skip(result.message) if result.skipped?

        raise failure_class, result.message
      end

      private

      def failure_class
        return RuntimeError unless defined?(::RSpec::Expectations::ExpectationNotMetError)

        ::RSpec::Expectations::ExpectationNotMetError
      end

      def register_thread_example
        ::RSpec.shared_examples "thread-safe under contention" do |threads: 8, iterations: 50, consistent: nil|
          it "survives #{threads} threads × #{iterations} calls" do
            options = { threads: threads, iterations: iterations, consistent: consistent }
            ConformanceKit::RSpec.enforce(self, Checks::ThreadContention.call(**options, &subject_call))
          end
        end
      end

      def register_fiber_example
        ::RSpec.shared_examples "fiber-safe under an Async reactor" do |fibers: 8, iterations: 50, consistent: nil|
          it "survives #{fibers} fibers × #{iterations} calls in one reactor" do
            options = { fibers: fibers, iterations: iterations, consistent: consistent }
            ConformanceKit::RSpec.enforce(self, Checks::FiberReactor.call(**options, &subject_call))
          end
        end
      end

      def register_boot_example
        ::RSpec.shared_examples "a boot-finalized configuration" do |readers:, finalize: nil|
          it "returns a Ractor-shareable value from every reader after finalize" do
            ConformanceKit::RSpec.enforce(self, Checks::BootFinalized.call(readers: readers, finalize: finalize))
          end
        end
      end

      def register_ractor_example
        ::RSpec.shared_examples "runs inside a non-main Ractor" do |inputs: []|
          it "returns the main Ractor's result from inside Ractor.new", :ractor do
            ConformanceKit::RSpec.enforce(self, Checks::RactorCanary.call(inputs: inputs, &subject_call))
          end
        end
      end
    end
  end
end

ConformanceKit::RSpec.register!

# frozen_string_literal: true

require "minitest" # never minitest/autorun: it would hook at_exit inside RSpec
require "conformance_kit/minitest"

RSpec.describe ConformanceKit::Minitest do
  def run_test(&body)
    klass = Class.new(Minitest::Test) do
      include ConformanceKit::Minitest

      define_method(:test_conformance, &body)
    end
    klass.new("test_conformance").run
  end

  def failure_message(result) = result.failures.map(&:message).join("\n")

  describe "#assert_thread_safe" do
    it "fails on the racy cache (violating fixture)" do
      result = run_test do
        cache = Fixtures::RacyCache.new(arrivals: 4)
        assert_thread_safe(threads: 4, iterations: 3, consistent: :identical) { cache.cache }
      end

      expect(result).not_to be_passed
      expect(failure_message(result)).to include("4 distinct results")
    end

    it "passes the locked cache (conforming fixture)" do
      result = run_test do
        cache = Fixtures::LockedCache.new
        assert_thread_safe(threads: 4, iterations: 3, consistent: :identical) { cache.cache }
      end

      expect(result).to be_passed
      expect(result.assertions).to eq(1)
    end
  end

  describe "#assert_fiber_safe" do
    it "fails on thread-scoped request state (violating fixture)" do
      result = run_test { assert_fiber_safe(fibers: 3, iterations: 2) { Fixtures::ThreadScopedContext.with(Object.new) } }

      expect(failure_message(result)).to include("request state leaked across fibers")
    end

    it "passes fiber-local request state (conforming fixture)" do
      result = run_test { assert_fiber_safe(fibers: 3, iterations: 2) { Fixtures::FiberLocalContext.with(Object.new) } }

      expect(result).to be_passed
    end
  end

  describe "#assert_boot_finalized" do
    it "fails naming the reader (violating fixture)" do
      result = run_test do
        assert_boot_finalized(readers: [Fixtures::LeakyConfig.method(:colors)], finalize: lambda {
          Fixtures::LeakyConfig.finalize!
        })
      end

      expect(failure_message(result)).to include("Fixtures::LeakyConfig.colors", "not frozen")
    end

    it "passes a deep-frozen configuration (conforming fixture)" do
      result = run_test do
        assert_boot_finalized(readers: [Fixtures::FinalizedConfig.method(:colors)], finalize: lambda {
          Fixtures::FinalizedConfig.finalize!
        })
      end

      expect(result).to be_passed
    end
  end

  describe "#assert_runs_in_ractor" do
    it "skips with a reason below Ruby 4.0" do
      allow(Ractor).to receive(:method_defined?).and_call_original
      allow(Ractor).to receive(:method_defined?).with(:value).and_return(false)
      result = run_test { assert_runs_in_ractor(inputs: [3]) { |number| Fixtures::PureMath.square(number) } }

      expect(result).to be_skipped
      expect(failure_message(result)).to include("Ruby 4.0")
    end

    context "on Ruby 4.0+", :ractor do
      before { skip "Ractor#value needs Ruby 4.0+ (#{RUBY_VERSION})" unless Ractor.method_defined?(:value) }

      it "passes a pure operation (conforming fixture)" do
        result = run_test { assert_runs_in_ractor(inputs: [3]) { |number| Fixtures::PureMath.square(number) } }

        expect(result).to be_passed
      end

      it "fails on an unshareable constant (violating fixture)" do
        result = run_test { assert_runs_in_ractor(inputs: [:one]) { |key| Fixtures::ConstantReader.lookup(key) } }

        expect(failure_message(result)).to include("Fixtures::ConstantReader::TABLE")
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe ConformanceKit::Checks::FiberReactor do
  context "when async is loadable" do
    before do
      require "async"
    rescue LoadError => e
      skip "the async gem is not installed on #{RUBY_VERSION}: #{e.message}"
    end

    it "fails when request state leaks across fibers (violating fixture)" do
      result = described_class.call(fibers: 4, iterations: 3) { Fixtures::ThreadScopedContext.with(Object.new) }

      expect(result).to be_failed
      expect(result.message).to include("fiber-safe under an Async reactor",
                                        "RuntimeError: request state leaked across fibers")
    end

    it "passes fiber-local request state (conforming fixture)" do
      result = described_class.call(fibers: 4, iterations: 3) { Fixtures::FiberLocalContext.with(Object.new) }

      expect(result).to be_passed
    end

    it "checks consistency of the results" do
      result = described_class.call(fibers: 3, iterations: 1, consistent: :identical) { Object.new }

      expect(result).to be_failed
      expect(result.message).to include("3 distinct")
    end
  end

  it "skips with a reason when async cannot be loaded" do
    loader = -> { raise LoadError, "cannot load such file -- async" }
    result = described_class.call(loader: loader) { :never_called }

    expect(result).to be_skipped
    expect(result.message).to include("async", "Gemfile")
  end
end

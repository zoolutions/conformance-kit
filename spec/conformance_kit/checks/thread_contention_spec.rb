# frozen_string_literal: true

RSpec.describe ConformanceKit::Checks::ThreadContention do
  let(:threads) { 8 }

  context "with a racy `@cache ||=` (violating fixture)" do
    it "fails, naming the distinct results, in 10 of 10 runs" do
      results = Array.new(10) do
        racy = Fixtures::RacyCache.new(arrivals: threads)
        described_class.call(threads: threads, iterations: 5, consistent: :identical) { racy.cache }
      end

      expect(results).to all(be_failed)
      expect(results.first.message).to include("thread-safe under contention", "#{threads} distinct", "Hash",
                                               ":identical")
    end
  end

  context "with a locked cache (conforming fixture)" do
    it "passes" do
      locked = Fixtures::LockedCache.new
      result = described_class.call(threads: threads, iterations: 5, consistent: :identical) { locked.cache }

      expect(result).to be_passed
    end
  end

  it "fails naming the exception when the call raises" do
    result = described_class.call(threads: 4, iterations: 2) { raise ArgumentError, "boom" }

    expect(result).to be_failed
    expect(result.message).to include("4 of 4 threads raised", "ArgumentError: boom")
  end

  it "accepts a callable consistency check" do
    counter = Queue.new
    result = described_class.call(threads: 2, iterations: 3, consistent: ->(all) { all.size == 6 }) { counter << 1 }

    expect(result).to be_passed
  end

  it "compares with == under consistent: :equal" do
    result = described_class.call(threads: 2, iterations: 2, consistent: :equal) { +"same" }

    expect(result).to be_passed
  end

  it "rejects an unknown consistency mode" do
    expect { described_class.call(consistent: :sorta) { 1 } }.to raise_error(ArgumentError, /consistent:/)
  end
end

# frozen_string_literal: true

RSpec.describe ConformanceKit::Checks::RactorCanary do
  context "on Ruby 4.0+", :ractor do
    before { skip "Ractor#value needs Ruby 4.0+ (#{RUBY_VERSION})" unless Ractor.method_defined?(:value) }

    it "passes a pure operation and compares with the main Ractor (conforming fixture)" do
      result = described_class.call(inputs: [7]) { |number| Fixtures::PureMath.square(number) }

      expect(result).to be_passed
    end

    it "fails naming the isolation error from inside the Ractor (violating fixture)" do
      result = described_class.call(inputs: [:one]) { |key| Fixtures::ConstantReader.lookup(key) }

      expect(result).to be_failed
      expect(result.message).to include("runs inside a non-main Ractor", "Ractor::IsolationError", "Fixtures::ConstantReader::TABLE")
    end

    it "fails with a hint when the block captures outer variables" do
      factor = 3
      result = described_class.call(inputs: [2]) { |number| number * factor }

      expect(result).to be_failed
      expect(result.message).to include("capture-free", "factor")
    end

    it "gives the Ractor the inputs as they were, even when the main run mutates them" do
      result = described_class.call(inputs: [[]]) { |list| list << :seen and list.size }

      expect(result).to be_passed
    end

    it "fails when the Ractor result differs from the main one" do
      result = described_class.call { Ractor.main? ? :main : :other }

      expect(result).to be_failed
      expect(result.message).to include(":other", ":main")
    end
  end

  it "skips with a reason when Ractor#value is unavailable" do
    allow(Ractor).to receive(:method_defined?).and_call_original
    allow(Ractor).to receive(:method_defined?).with(:value).and_return(false)
    result = described_class.call { :never }

    expect(result).to be_skipped
    expect(result.message).to include("Ruby 4.0", RUBY_VERSION)
  end
end

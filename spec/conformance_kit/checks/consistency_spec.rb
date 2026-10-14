# frozen_string_literal: true

RSpec.describe ConformanceKit::Checks::Consistency do
  describe ".problem with consistent: :equal" do
    let(:counting) do
      Struct.new(:id, :calls) do
        def ==(other)
          calls << 1
          other.is_a?(self.class) && other.id == id
        end
      end
    end

    it "stays linear in == calls when every result differs" do
      calls = []
      results = Array.new(500) { counting.new(_1, calls) }

      problem = described_class.problem(results, :equal)

      expect(problem).to include("more than 10 distinct results")
      expect(calls.size).to be < 500 * 11
    end

    it "counts the distinct results exactly below the cap" do
      results = [1, 2, 3, 2.0, 1]

      expect(described_class.problem(results, :equal)).to include("returned 3 distinct results")
    end
  end
end

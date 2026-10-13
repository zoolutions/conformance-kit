# frozen_string_literal: true

RSpec.describe ConformanceKit::Store do
  let(:key) { :"conformance_kit_store_spec_#{SecureRandom.hex(4)}" }

  shared_examples "a lazy store" do
    it "runs the initializer once and returns the same object afterwards" do
      calls = 0
      first = described_class.fetch(key) do
        calls += 1
        +"value"
      end
      second = described_class.fetch(key) do
        calls += 1
        +"other"
      end

      expect(second).to equal(first)
      expect(calls).to eq(1)
    end

    it "returns the same object to every thread of one Ractor" do
      start = Queue.new
      threads = Array.new(8) do
        Thread.new do
          start.pop
          described_class.fetch(key) { Object.new }
        end
      end
      8.times { start << true }

      expect(threads.map(&:value).uniq(&:object_id).size).to eq(1)
    end

    it "keeps keys apart" do
      a = described_class.fetch(:"#{key}_a") { :a }
      b = described_class.fetch(:"#{key}_b") { :b }

      expect([a, b]).to eq(%i[a b])
    end
  end

  context "with the running Ruby's capability" do
    it_behaves_like "a lazy store"

    it "reports whether it uses Ractor.store_if_absent" do
      native = defined?(Ractor) ? Ractor.respond_to?(:store_if_absent) : false

      expect(described_class.native?).to eq(native)
    end
  end

  context "when Ractor.store_if_absent is unavailable (the fallback)" do
    before do
      allow(described_class).to receive(:native?).and_return(false)
      if defined?(Ractor) && Ractor.respond_to?(:store_if_absent)
        allow(Ractor).to receive(:store_if_absent).and_raise("the fallback must not call store_if_absent")
      end
    end

    it_behaves_like "a lazy store"
  end

  context "when Ractor.store_if_absent is available", if: defined?(Ractor) && Ractor.respond_to?(:store_if_absent) do
    it "delegates to it" do
      allow(Ractor).to receive(:store_if_absent).and_call_original
      described_class.fetch(key) { 1 }

      expect(Ractor).to have_received(:store_if_absent).with(key)
    end
  end

  context "inside a non-main Ractor", :ractor do
    before do
      skip "Ractor#value needs Ruby 4.0+ (#{RUBY_VERSION})" unless defined?(Ractor) && Ractor.method_defined?(:value)
    end

    it "gives each Ractor its own value" do
      main = described_class.fetch(:conformance_kit_store_per_ractor) { Object.new }
      other = Ractor.new do
        ConformanceKit::Store.fetch(:conformance_kit_store_per_ractor) do
          Object.new
        end.object_id
      end.value

      expect(other).not_to eq(main.object_id)
    end
  end
end

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

  context "on a non-main Ractor's fallback (Ractor-local storage, Ruby 3.2/3.3)", if: defined?(Ractor) do
    before do
      allow(described_class).to receive_messages(native?: false, main_ractor?: false)
    end

    it_behaves_like "a lazy store"

    it "hands every thread the first value published when they race on the build" do
      arrived = Queue.new
      release = Queue.new
      threads = Array.new(8) do
        Thread.new do
          described_class.fetch(key) do
            arrived << true
            release.pop # every thread is inside the initializer before any finishes
            Object.new
          end
        end
      end
      8.times { arrived.pop }
      8.times { release << true }

      expect(threads.map(&:value).uniq(&:object_id).size).to eq(1)
    end
  end

  context "when Ractor.store_if_absent is available", if: defined?(Ractor) && Ractor.respond_to?(:store_if_absent) do
    it "delegates to it" do
      allow(Ractor).to receive(:store_if_absent).and_call_original
      described_class.fetch(key) { 1 }

      expect(Ractor).to have_received(:store_if_absent).with(key)
    end
  end

  context "inside a non-main Ractor on the fallback path (Ruby 3.2/3.3)", :ractor do
    before do
      skip "no Ractor on #{RUBY_ENGINE}" unless defined?(Ractor)
      if described_class.native?
        skip "Ractor.store_if_absent exists on #{RUBY_VERSION}: the native path is covered below"
      end
    end

    it "keeps a per-Ractor value instead of touching the main-only fallback" do
      main = described_class.fetch(:conformance_kit_store_fallback_ractor) { Object.new }
      ractor = Ractor.new do
        first = ConformanceKit::Store.fetch(:conformance_kit_store_fallback_ractor) { Object.new }
        [first.__id__, ConformanceKit::Store.fetch(:conformance_kit_store_fallback_ractor) { :again }.__id__]
      end
      ids = ractor.respond_to?(:value) ? ractor.value : ractor.take

      expect(ids.uniq.size).to eq(1)
      expect(ids.first).not_to eq(main.__id__)
    end

    it "caches a nil or false value instead of rerunning the initializer" do
      ractor = Ractor.new do
        calls = 0
        2.times { ConformanceKit::Store.fetch(:conformance_kit_store_fallback_nil) { calls += 1 and nil } }
        2.times { ConformanceKit::Store.fetch(:conformance_kit_store_fallback_false) { calls += 1 and false } }
        calls
      end

      expect(ractor.respond_to?(:value) ? ractor.value : ractor.take).to eq(2)
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

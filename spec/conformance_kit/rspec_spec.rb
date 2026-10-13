# frozen_string_literal: true

require "conformance_kit/rspec"

RSpec.describe ConformanceKit::RSpec do
  def only(examples)
    expect(examples.size).to eq(1)
    examples.values.first
  end

  describe '"thread-safe under contention"' do
    it "fails on the racy cache (violating fixture), naming the distinct results" do
      example = only(run_sandboxed do
        let(:subject_call) { cache = Fixtures::RacyCache.new(arrivals: 4) and -> { cache.cache } }

        it_behaves_like "thread-safe under contention", threads: 4, iterations: 3, consistent: :identical
      end)

      expect(example.execution_result.status).to eq(:failed)
      expect(example.execution_result.exception.message).to include("4 distinct results", "Hash")
    end

    it "passes the locked cache (conforming fixture)" do
      example = only(run_sandboxed do
        let(:subject_call) { cache = Fixtures::LockedCache.new and -> { cache.cache } }

        it_behaves_like "thread-safe under contention", threads: 4, iterations: 3, consistent: :identical
      end)

      expect(example.execution_result.status).to eq(:passed)
    end
  end

  describe '"fiber-safe under an Async reactor"' do
    it "fails on thread-scoped request state (violating fixture)" do
      example = only(run_sandboxed do
        let(:subject_call) { -> { Fixtures::ThreadScopedContext.with(Object.new) } }

        it_behaves_like "fiber-safe under an Async reactor", fibers: 3, iterations: 2
      end)

      expect(example.execution_result.status).to eq(:failed)
      expect(example.execution_result.exception.message).to include("request state leaked across fibers")
    end

    it "passes fiber-local request state (conforming fixture)" do
      example = only(run_sandboxed do
        let(:subject_call) { -> { Fixtures::FiberLocalContext.with(Object.new) } }

        it_behaves_like "fiber-safe under an Async reactor", fibers: 3, iterations: 2
      end)

      expect(example.execution_result.status).to eq(:passed)
    end
  end

  describe '"a boot-finalized configuration"' do
    it "fails naming the reader and the unfrozen Array (violating fixture)" do
      example = only(run_sandboxed do
        it_behaves_like "a boot-finalized configuration",
                        readers: [Fixtures::LeakyConfig.method(:colors)],
                        finalize: -> { Fixtures::LeakyConfig.finalize! }
      end)

      expect(example.execution_result.status).to eq(:failed)
      expect(example.execution_result.exception.message).to include("Fixtures::LeakyConfig.colors", "[:primary]",
                                                                    "not frozen")
    end

    it "passes a deep-frozen configuration (conforming fixture)" do
      example = only(run_sandboxed do
        it_behaves_like "a boot-finalized configuration",
                        readers: [Fixtures::FinalizedConfig.method(:colors)],
                        finalize: -> { Fixtures::FinalizedConfig.finalize! }
      end)

      expect(example.execution_result.status).to eq(:passed)
    end
  end

  describe '"runs inside a non-main Ractor"' do
    it "is tagged :ractor" do
      example = only(run_sandboxed do
        let(:subject_call) { ->(number) { Fixtures::PureMath.square(number) } }

        it_behaves_like "runs inside a non-main Ractor", inputs: [3]
      end)

      expect(example.metadata[:ractor]).to be(true)
    end

    it "skips with a reason below Ruby 4.0" do
      allow(Ractor).to receive(:method_defined?).and_call_original
      allow(Ractor).to receive(:method_defined?).with(:value).and_return(false)
      example = only(run_sandboxed do
        let(:subject_call) { ->(number) { Fixtures::PureMath.square(number) } }

        it_behaves_like "runs inside a non-main Ractor", inputs: [3]
      end)

      expect(example.execution_result.status).to eq(:pending)
      expect(example.execution_result.pending_message).to include("Ruby 4.0")
    end

    context "on Ruby 4.0+", :ractor do
      before { skip "Ractor#value needs Ruby 4.0+ (#{RUBY_VERSION})" unless Ractor.method_defined?(:value) }

      it "passes a pure operation (conforming fixture)" do
        example = only(run_sandboxed do
          let(:subject_call) { ->(number) { Fixtures::PureMath.square(number) } }

          it_behaves_like "runs inside a non-main Ractor", inputs: [3]
        end)

        expect(example.execution_result.status).to eq(:passed)
      end

      it "fails on an unshareable constant (violating fixture)" do
        example = only(run_sandboxed do
          let(:subject_call) { ->(key) { Fixtures::ConstantReader.lookup(key) } }

          it_behaves_like "runs inside a non-main Ractor", inputs: [:one]
        end)

        expect(example.execution_result.status).to eq(:failed)
        expect(example.execution_result.exception.message).to include("Fixtures::ConstantReader::TABLE")
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe ConformanceKit::Checks::BootFinalized do
  it "fails naming the reader, the path and the class of an unshareable value (violating fixture)" do
    result = described_class.call(
      readers: [Fixtures::LeakyConfig.method(:colors), Fixtures::LeakyConfig.method(:name_value)],
      finalize: -> { Fixtures::LeakyConfig.finalize! }
    )

    expect(result).to be_failed
    expect(result.message).to include("1 of 2 readers", "Fixtures::LeakyConfig.colors", "[:primary]", "Array",
                                      "not frozen")
    expect(result.message).not_to include("LeakyConfig.name_value")
  end

  it "passes a deep-frozen configuration (conforming fixture)" do
    result = described_class.call(
      readers: [Fixtures::FinalizedConfig.method(:colors), Fixtures::FinalizedConfig.method(:name_value)],
      finalize: -> { Fixtures::FinalizedConfig.finalize! }
    )

    expect(result).to be_passed
  end

  it "names Hash readers by their key" do
    result = described_class.call(readers: { "Config.handler" => -> { proc { 1 } } })

    expect(result.message).to include("Config.handler", "Proc", "shareable_proc")
  end

  it "words each offense as one sentence, at the top level and nested" do
    result = described_class.call(readers: {
                                    "Config.handler" => -> { proc { 1 } },
                                    "Config.hooks" => -> { { save: proc { 1 } } },
                                    "Config.lock" => -> { Mutex.new },
                                    "Config.locks" => -> { { main: Mutex.new } }
                                  })
    never = "never shareable: use Ractor.shareable_proc (Ruby 4.0) or Ractor.make_shareable on a capture-free proc"
    main_only = "main-only: keep per-Ractor state in ConformanceKit::Store, or allowlist it main_only"

    expect(result.message.lines.drop(1).map(&:strip)).to eq(
      ["Config.handler returned Proc: it is a Proc that is #{never}",
       "Config.hooks returned Hash: [:save] is a Proc that is #{never}",
       "Config.lock returned Thread::Mutex: it is a Thread::Mutex that is #{main_only}",
       "Config.locks returned Hash: [:main] is a Thread::Mutex that is #{main_only}"]
    )
  end

  it "names a bare lambda by its source location" do
    reader = -> { [] }
    result = described_class.call(readers: [reader])

    expect(result.message).to include("#{__FILE__}:#{__LINE__ - 3}")
  end

  it "rejects an empty readers: list, which would certify nothing" do
    expect { described_class.call(readers: []) }.to raise_error(ArgumentError, /readers:/)
    expect { described_class.call(readers: {}) }.to raise_error(ArgumentError, /readers:/)
  end

  it "reports a reader that raises" do
    result = described_class.call(readers: { "Config.broken" => -> { raise KeyError, "nope" } })

    expect(result).to be_failed
    expect(result.message).to include("Config.broken", "KeyError: nope")
  end

  it "skips with a reason without Ractor" do
    result = without_ractor { described_class.call(readers: [-> { 1 }]) }

    expect(result).to be_skipped
    expect(result.message).to include("Ractor")
  end
end

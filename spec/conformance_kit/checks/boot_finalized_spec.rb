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
    hide_const("Ractor")
    result = described_class.call(readers: [-> { 1 }])

    expect(result).to be_skipped
    expect(result.message).to include("Ractor")
  end
end

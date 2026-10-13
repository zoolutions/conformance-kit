# frozen_string_literal: true

RSpec.describe ConformanceKit::Shareability do
  it "returns nil for a shareable value" do
    expect(described_class.culprit(Ractor.make_shareable({ a: [1] }))).to be_nil
  end

  it "points at the unfrozen collection itself" do
    culprit = described_class.culprit([1, 2])

    expect(culprit.path).to eq("")
    expect(culprit.reason).to include("Array", "not frozen")
  end

  it "walks into frozen containers to the deepest offender" do
    value = { list: [1, { deep: [] }.freeze].freeze }.freeze
    culprit = described_class.culprit(value)

    expect(culprit.path).to eq("[:list][1][:deep]")
    expect(culprit.object_class).to eq("Array")
  end

  it "walks into instance variables" do
    holder = Object.new
    holder.instance_variable_set(:@lock, Mutex.new)
    culprit = described_class.culprit(holder.freeze)

    expect(culprit.path).to eq(".@lock")
    expect(culprit.reason).to include("Thread::Mutex", "ConformanceKit::Store")
  end

  it "names a Proc and the fix" do
    expect(described_class.culprit(proc { 1 }.freeze).reason).to include("Proc", "Ractor.shareable_proc")
  end

  it "blames a lock inside an unfrozen container, not the container" do
    culprit = described_class.culprit({ lock: Mutex.new })

    expect(culprit.path).to eq("[:lock]")
    expect(culprit.object_class).to eq("Thread::Mutex")
  end

  it "names a frozen Hash's default_proc" do
    culprit = described_class.culprit(Hash.new { |h, k| h[k] = [] }.freeze)

    expect(culprit.path).to eq(".default_proc")
    expect(culprit.object_class).to eq("Proc")
  end

  it "names an UnboundMethod as never shareable" do
    expect(described_class.culprit(Module.instance_method(:name).freeze).reason).to include("UnboundMethod",
                                                                                            "never shareable")
  end

  it "survives cycles" do
    list = [[]]
    list << list

    expect(described_class.culprit(list.freeze).path).to eq("[0]")
  end
end

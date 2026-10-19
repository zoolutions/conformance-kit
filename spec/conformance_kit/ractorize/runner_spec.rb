# frozen_string_literal: true

require "conformance_kit/ractorize/runner"
require "tmpdir"

RSpec.describe ConformanceKit::Ractorize::Runner do
  let(:out) { StringIO.new }

  def runner_for(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".conformance.yml")
      File.write(path, yaml)
      yield described_class.new(ConformanceKit::Config.load(path), out: out)
    end
  end

  it "skips with the reason, exit 0, where Ractor#value is unavailable (below Ruby 4.0, no Ractor)" do
    allow(ConformanceKit::Ractorize).to receive(:available?).and_return(false)

    runner_for("ractorize:\n  app: .\n") { expect(_1.run).to eq(0) }
    expect(out.string).to include("ractorize: skipped:", "Ractor#value", RUBY_VERSION)
  end

  it "skips with the reason, exit 0, when Rails is not in the bundle" do
    skip "this bundle has Rails (the ractorize lane)" if Gem.loaded_specs.key?("railties")

    allow(ConformanceKit::Ractorize).to receive(:available?).and_return(true)

    runner_for("ractorize:\n  app: .\n") { expect(_1.run).to eq(0) }
    expect(out.string).to include("ractorize: skipped:", "Rails is not in the bundle", "Gemfile.ractorize")
  end
end

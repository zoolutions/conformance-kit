# frozen_string_literal: true

require "open3"

# The ractorize job proven both ways against real Rails apps. Runs in the
# ractorize lane only (Ruby 4.0, BUNDLE_GEMFILE=Gemfile.ractorize, CI's
# "Ractorize lane" job); everywhere else it skips with the reason.
RSpec.describe "conformance-kit check --ractorize on the fixture apps", :ractorize do
  let(:root) { File.expand_path("../../..", __dir__) }
  let(:fixtures) { File.join(root, "spec/fixtures/ractorize") }

  before do
    unless Gem.loaded_specs.key?("railties") && defined?(Ractor) && Ractor.method_defined?(:value)
      skip "needs the ractorize lane: Ruby 4.0 and BUNDLE_GEMFILE=Gemfile.ractorize (Rails main)"
    end
  end

  def check(name)
    output, status = Open3.capture2e(RbConfig.ruby, File.join(root, "exe/conformance-kit"), "check", "--ractorize",
                                     "--config", File.join(fixtures, name, ".conformance.yml"))
    [output, status.exitstatus]
  end

  def line_of(name, file, text)
    path = File.join(fixtures, name, file)
    "#{path}:#{File.readlines(path).index { _1.include?(text) } + 1}"
  end

  it "fails an engine that appends a route block from an initializer, at boot, naming the block" do
    output, status = check("violating_boot")

    expect(status).to eq(1), output
    expect(output).to include("ractorize: boot failed", "Proc's self is not shareable",
                              line_of("violating_boot", "lib/violating_boot_engine.rb", "app.routes.append do"))
  end

  it "fails a render that reads a shallow-frozen class ivar, naming the request, the ivar and the line" do
    output, status = check("violating_render")

    expect(status).to eq(1), output
    expect(output).to include("GET /widget -> 500 (0 bytes): Ractor::IsolationError",
                              "(@registry from ViolatingRenderEngine::Widget)",
                              line_of("violating_render", "app/controllers/widgets_controller.rb", "Widget.registry"))
    expect(output).to include("audit ViolatingRenderEngine after ractorize!: 1 findings",
                              "ViolatingRenderEngine::Widget.@registry (class ivar) Hash: [:names] is an Array")
  end

  it "passes the conforming engine" do
    output, status = check("conforming")

    expect(status).to eq(0), output
    expect(output).to include("ractorize: Rails.application.ractorize!: ok", "GET /widget -> 200 (10 bytes)",
                              "ractorize: audit ConformingEngine after ractorize!: 0 findings", "ractorize passed")
  end
end

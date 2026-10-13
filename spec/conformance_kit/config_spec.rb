# frozen_string_literal: true

require "json"
require "open3"
require "yaml"

RSpec.describe "config/ and the reusable workflows" do
  let(:root) { File.expand_path("../..", __dir__) }

  def load_yaml(path) = YAML.safe_load_file(File.join(root, path))

  def rubocop(config, file)
    out, err, = Open3.capture3("bundle", "exec", "rubocop", "--config", config, "--format", "json", file, chdir: root)
    JSON.parse(out).fetch("files").flat_map { _1["offenses"] }.map { _1["cop_name"] }.uniq
  rescue JSON::ParserError
    raise "rubocop printed no JSON: #{err}"
  end

  describe "config/rubocop.yml" do
    let(:config) { load_yaml("config/rubocop.yml") }
    let(:six) do
      %w[ClassAndModuleAttributes ClassInstanceVariable MutableClassInstanceVariable NewThread DirChdir
         RackMiddlewareInstanceVariable].map { "ThreadSafety/#{_1}" }
    end

    it "loads rubocop-thread_safety and turns all six cops on" do
      expect(config["plugins"]).to include("rubocop-thread_safety")
      expect(six.map { config.dig(_1, "Enabled") }).to all(be(true))
      expect(config.dig("ThreadSafety/MutableClassInstanceVariable", "EnforcedStyle")).to eq("literals")
    end

    it "flags the violating fixture" do
      cops = rubocop("config/rubocop.yml", "spec/fixtures/rubocop/violating.rb")

      expect(cops).to include("ThreadSafety/ClassInstanceVariable", "ThreadSafety/NewThread",
                              "ThreadSafety/ClassAndModuleAttributes", "ThreadSafety/LazySynchronizationPrimitive")
    end

    it "passes the conforming fixture" do
      expect(rubocop("config/rubocop.yml", "spec/fixtures/rubocop/conforming.rb").grep(/ThreadSafety/)).to be_empty
    end
  end

  describe "config/rubocop_spinel.yml" do
    it "runs only the Spinel cops" do
      config = load_yaml("config/rubocop_spinel.yml")

      expect(config["plugins"]).to eq(["rubocop_spinel"])
      expect(config.dig("AllCops", "DisabledByDefault")).to be(true)
      expect(config.dig("Spinel/Unsupported", "Enabled")).to be(true)
    end

    it "flags `class << self` and threads in the violating fixture, and nothing else" do
      expect(rubocop("config/rubocop_spinel.yml", "spec/fixtures/rubocop/violating.rb")).to eq(["Spinel/Unsupported"])
    end
  end

  shared_examples "a reusable workflow" do |path|
    let(:workflow) { load_yaml(path) }
    # Psych reads the bare `on:` key as the boolean true.
    let(:inputs) { workflow.fetch(true).fetch("workflow_call").fetch("inputs") }
    let(:steps) { workflow.fetch("jobs").values.flat_map { _1.fetch("steps") } }

    it "is callable with workflow_call and read-only" do
      expect(workflow.fetch(true).keys).to eq(["workflow_call"])
      expect(workflow.fetch("permissions")).to eq("contents" => "read")
    end

    it "pins every action by SHA" do
      expect(steps.filter_map { _1["uses"] }).to all(match(/@[0-9a-f]{40}\z/))
    end

    it "never interpolates an input into a run: script" do
      expect(steps.filter_map { _1["run"] }.grep(/\$\{\{/)).to be_empty
    end
  end

  describe ".github/workflows/ractor.yml" do
    it_behaves_like "a reusable workflow", ".github/workflows/ractor.yml"

    let(:workflow) { load_yaml(".github/workflows/ractor.yml") }
    let(:inputs) { workflow.fetch(true).fetch("workflow_call").fetch("inputs") }

    it "takes the audit target and defaults to Ruby 4.0 and the :ractor tag" do
      expect(inputs.keys).to contain_exactly("ruby-version", "require", "namespace", "allowlist", "test-command",
                                             "audit", "working-directory")
      expect(inputs.slice("require", "namespace").values.map { _1["required"] }).to all(be(true))
      expect(inputs.dig("ruby-version", "default")).to eq("4.0")
      expect(inputs.dig("test-command", "default")).to eq("bundle exec rspec --tag ractor")
    end

    it "runs conformance-audit --strict" do
      runs = workflow.fetch("jobs").values.flat_map { _1["steps"] }.filter_map { _1["run"] }.join("\n")

      expect(runs).to include("conformance-audit", "--strict")
    end
  end

  describe ".github/workflows/probes.yml" do
    it_behaves_like "a reusable workflow", ".github/workflows/probes.yml"

    let(:workflow) { load_yaml(".github/workflows/probes.yml") }
    let(:inputs) { workflow.fetch(true).fetch("workflow_call").fetch("inputs") }
    let(:steps) { workflow.fetch("jobs").values.flat_map { _1.fetch("steps") } }

    it "takes the gem and the optional roundhouse app" do
      expect(inputs.keys).to contain_exactly("gem-name", "ruby-version", "paths", "roundhouse-app",
                                             "roundhouse-version", "artifact-name", "working-directory")
      expect(inputs.dig("gem-name", "required")).to be(true)
      expect(inputs.dig("roundhouse-app", "default")).to eq("")
    end

    it "never fails the build: every probe step continues on error" do
      probes = steps.select { _1["name"].to_s.start_with?("Probe:") }

      expect(probes.map { _1["name"] }).to contain_exactly("Probe: rubocop_spinel", "Probe: spinel-compat",
                                                           "Probe: roundhouse check")
      expect(probes.map { _1["continue-on-error"] }).to all(be(true))
    end

    it "uploads the reports as an artifact even when a probe failed" do
      upload = steps.find { _1["uses"].to_s.start_with?("actions/upload-artifact@") }

      expect(upload["if"]).to eq("always()")
    end
  end
end

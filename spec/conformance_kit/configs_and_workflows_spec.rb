# frozen_string_literal: true

require "json"
require "open3"
require "yaml"

RSpec.describe "config/ and the conformance workflow" do
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

  describe ".github/workflows/conformance.yml" do
    let(:workflow) { load_yaml(".github/workflows/conformance.yml") }
    let(:jobs) { workflow.fetch("jobs") }
    let(:steps) { jobs.values.flat_map { _1.fetch("steps") } }
    let(:runs) { steps.filter_map { _1["run"] }.join("\n") }
    let(:probes) { jobs.fetch("probes").fetch("steps") }

    it "is a reusable workflow only (each repo calls it), read-only, with no inputs or secrets" do
      # Psych reads the bare `on:` key as the boolean true.
      expect(workflow.fetch(true)).to eq("workflow_call" => nil)
      expect(workflow.fetch("permissions")).to eq("contents" => "read")
    end

    it "pins every action by SHA and never persists credentials" do
      expect(steps.filter_map { _1["uses"] }).to all(match(/@[0-9a-f]{40}\z/))
      checkouts = steps.select { _1["uses"].to_s.start_with?("actions/checkout@") }
      expect(checkouts.map { _1.dig("with", "persist-credentials") }).to all(be(false))
    end

    it "never interpolates an expression into a run: script" do
      expect(steps.filter_map { _1["run"] }.grep(/\$\{\{/)).to be_empty
    end

    it "never references itself or another workflow by @ref" do
      expect(File.read(File.join(root, ".github/workflows/conformance.yml"))).not_to match(%r{workflows/\S+@})
    end

    it "gives the conformance job a postgres:18 service without exporting a database URL" do
      job = jobs.fetch("ractor")

      expect(job.dig("services", "postgres", "image")).to eq("postgres:18")
      expect(job.to_s).not_to match(/DATABASE_URL/)
    end

    it "reads the Ruby and working directory with yq before the gem is installed" do
      expect(workflow.dig("env", "CONFORMANCE_CONFIG")).to eq(".conformance.yml")
      expect(jobs.fetch("settings").fetch("steps").filter_map { _1["run"] }.join)
        .to include("yq '.ractor.ruby", "yq '.ractor.working_directory", "$CONFORMANCE_CONFIG")
    end

    it "checks the version handshake from job.workflow_ref (its own tag, not the caller's), then runs check" do
      handshake = jobs.fetch("ractor").fetch("steps").find { _1["name"] == "Version handshake" }

      expect(handshake.dig("env", "WORKFLOW_REF")).to eq("${{ job.workflow_ref }}")
      expect(handshake["run"]).to include("refs/tags/v", "bump conformance-kit to ~>")
      expect(runs).to include("bundle exec conformance-kit check")
    end

    it "reads the probe inputs through conformance-kit config" do
      expect(runs).to include("bundle exec conformance-kit config", "config probes.gem_name", "config probes.paths",
                              "config probes.roundhouse_app")
    end

    it "never fails the workflow from the probes job, even on a setup or upload failure" do
      expect(jobs.fetch("probes")["continue-on-error"]).to be(true)
    end

    it "rejects an absolute or escaping working directory" do
      script = jobs.fetch("settings").fetch("steps").filter_map { _1["run"] }.join

      expect(script).to include('"$dir" == /*', '"$dir" == *..*')
    end

    it "never fails the build from a probe: every probe step continues on error" do
      named = probes.select { _1["name"].to_s.start_with?("Probe:") }

      expect(named.map { _1["name"] }).to contain_exactly("Probe: rubocop_spinel", "Probe: spinel-compat",
                                                          "Probe: roundhouse check")
      expect(named.map { _1["continue-on-error"] }).to all(be(true))
    end

    it "checks the roundhouse binary against a pinned digest, never piping an installer to sh" do
      script = probes.find { _1["name"] == "Probe: roundhouse check" }.fetch("run")

      expect(jobs.fetch("probes").dig("env", "ROUNDHOUSE_SHA256")).to match(/\A\h{64}\z/)
      expect(script).to include("sha256sum --check")
      expect(script).not_to match(/\|\s*sh\b/)
    end

    it "uploads the reports as an artifact and writes a summary even when a probe failed" do
      upload = probes.find { _1["uses"].to_s.start_with?("actions/upload-artifact@") }
      summary = probes.find { _1["name"] == "Summary" }

      expect([upload["if"], summary["if"]]).to all(eq("always()"))
    end

    it "keeps rubocop_spinel out of the bundle: gem-installed in the probe only" do
      expect(runs).to include("gem install rubocop_spinel --version 0.2.0")
    end
  end

  describe ".github/workflows/conformance-self.yml" do
    let(:caller) { load_yaml(".github/workflows/conformance-self.yml") }

    it "calls conformance.yml from this checkout on pull_request and merge_group, the way a consumer would" do
      expect(caller.fetch(true).keys).to contain_exactly("pull_request", "merge_group")
      expect(caller.fetch("permissions")).to eq("contents" => "read")
      expect(caller.fetch("jobs")).to eq("conformance" => { "uses" => "./.github/workflows/conformance.yml" })
    end
  end

  it "ships no 0.1 reusable workflows" do
    expect(%w[ractor.yml probes.yml].map { File.exist?(File.join(root, ".github/workflows", _1)) }).to all(be(false))
  end
end

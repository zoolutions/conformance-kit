# frozen_string_literal: true

require "conformance_kit/cli"
require "open3"
require "tmpdir"

RSpec.describe ConformanceKit::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:root) { File.expand_path("../..", __dir__) }
  let(:rubocop_yml) { "inherit_gem:\n  conformance-kit: config/rubocop.yml\n" }

  def run_cli(*argv, **) = described_class.run(argv, out: out, err: err, **)
  def project(name, file = ".conformance.yml") = File.join(root, "spec/fixtures/projects", name, file)

  def with_project(conformance, rubocop: rubocop_yml)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".conformance.yml"), conformance) if conformance
      File.write(File.join(dir, ".rubocop.yml"), rubocop) if rubocop
      yield File.join(dir, ".conformance.yml"), dir
    end
  end

  it "exits 2 on an unknown subcommand, printing the usage" do
    expect(run_cli("frobnicate")).to eq(2)
    expect(err.string).to include("frobnicate", "check", "doctor", "config")
  end

  it "exits 2 without a subcommand" do
    expect(run_cli).to eq(2)
  end

  describe "config KEY" do
    it "prints a scalar" do
      expect(run_cli("config", "probes.gem_name", "--config", File.join(root, ".conformance.yml"))).to eq(0)
      expect(out.string).to eq("conformance-kit\n")
    end

    it "prints a list joined with spaces" do
      expect(run_cli("config", "probes.paths", "--config", project("clean"))).to eq(0)
      expect(out.string).to eq("lib\n")
    end

    it "prints a default for an unset key" do
      expect(run_cli("config", "ractor.ruby", "--config", project("clean"))).to eq(0)
      expect(out.string).to eq("4.0\n")
    end

    it "prints an empty line for an unset key without a default, and exits 0" do
      expect(run_cli("config", "probes.gem_name", "--config", project("clean"))).to eq(0)
      expect(out.string).to eq("\n")
    end

    it "reads a missing file as empty" do
      expect(run_cli("config", "probes.gem_name", "--config", File.join(Dir.tmpdir, "none", ".conformance.yml")))
        .to eq(0)
    end

    it "prints env as NAME=value lines" do
      with_project("ractor:\n  env:\n    A: one\n    B: two\n") do |path|
        expect(run_cli("config", "ractor.env", "--config", path)).to eq(0)
        expect(out.string).to eq("A=one\nB=two\n")
      end
    end

    it "exits 2 on an unknown key, naming it" do
      expect(run_cli("config", "probes.gem", "--config", project("clean"))).to eq(2)
      expect(err.string).to include("probes.gem")
    end

    it "exits 2 on extra arguments after the key" do
      expect(run_cli("config", "probes.gem_name", "typo", "--config", project("clean"))).to eq(2)
      expect(err.string).to include("typo")
    end

    it "exits 2 on a --config that is a directory" do
      expect(run_cli("config", "probes.gem_name", "--config", root)).to eq(2)
      expect(err.string).to include(root)
    end

    it "exits 2 without a key" do
      expect(run_cli("config")).to eq(2)
      expect(err.string).to include("KEY")
    end

    it "exits 2 on an invalid config" do
      with_project("ractor:\n  ruby: 4.0\n") do |path|
        expect(run_cli("config", "ractor.ruby", "--config", path)).to eq(2)
        expect(err.string).to include("ractor.ruby", "string")
      end
    end
  end

  describe "doctor" do
    let(:specs) { { "rubocop-thread_safety" => Gem::Specification.new("rubocop-thread_safety", "0.8.0") } }

    def doctor(path, *args, version: "0.2.0", specs: self.specs)
      run_cli("doctor", "--config", path, *args, version: version, specs: specs)
    end

    it "passes a conforming setup" do
      expect(doctor(project("clean"))).to eq(0)
      expect(out.string).to include("ok")
    end

    it "fails without .conformance.yml, naming the fix" do
      with_project(nil) do |path|
        expect(doctor(path)).to eq(1)
        expect(out.string).to include(".conformance.yml", "audit.namespace")
      end
    end

    it "fails without audit.namespace" do
      with_project("ractor:\n  ruby: '4.0'\n") do |path|
        expect(doctor(path)).to eq(1)
        expect(out.string).to include("audit.namespace")
      end
    end

    it "fails when .rubocop.yml does not inherit the kit's config, naming the fix" do
      with_project("audit:\n  namespace: [X]\n", rubocop: "plugins:\n  - rubocop-thread_safety\n") do |path|
        expect(doctor(path)).to eq(1)
        expect(out.string).to include(".rubocop.yml", "inherit_gem", "conformance-kit: config/rubocop.yml")
      end
    end

    it "fails, not crashes, on a scalar inherit_gem" do
      with_project("audit:\n  namespace: [X]\n", rubocop: "inherit_gem: conformance-kit\n") do |path|
        expect(doctor(path)).to eq(1)
        expect(out.string).to include("inherit_gem")
      end
    end

    it "fails without a .rubocop.yml" do
      with_project("audit:\n  namespace: [X]\n", rubocop: nil) do |path|
        expect(doctor(path)).to eq(1)
        expect(out.string).to include(".rubocop.yml")
      end
    end

    it "accepts inherit_gem with a list of files" do
      rubocop = "inherit_gem:\n  conformance-kit:\n    - config/rubocop.yml\n"
      with_project("audit:\n  namespace: [X]\n", rubocop: rubocop) do |path|
        expect(doctor(path)).to eq(0), out.string
      end
    end

    it "fails without rubocop-thread_safety in the bundle, naming the Gemfile line" do
      expect(doctor(project("clean"), specs: {})).to eq(1)
      expect(out.string).to include('gem "rubocop-thread_safety", ">= 0.8"')
    end

    it "fails on rubocop-thread_safety below 0.8" do
      old = { "rubocop-thread_safety" => Gem::Specification.new("rubocop-thread_safety", "0.7.2") }

      expect(doctor(project("clean"), specs: old)).to eq(1)
      expect(out.string).to include("0.7.2", ">= 0.8")
    end

    it "passes --expect when the resolved conformance-kit is at least that version" do
      expect(doctor(project("clean"), "--expect", "0.2", version: "0.2.0")).to eq(0)
      expect(doctor(project("clean"), "--expect", "0.2", version: "0.3.1")).to eq(0)
    end

    it "fails --expect against an older conformance-kit with the bump message" do
      expect(doctor(project("clean"), "--expect", "0.2", version: "0.1.0")).to eq(1)
      expect(out.string).to include("0.1.0", "bump conformance-kit to ~> 0.2")
    end

    it "exits 2 on a malformed --expect" do
      expect(doctor(project("clean"), "--expect", "v0.2")).to eq(2)
      expect(err.string).to include("v0.2")
    end

    it "lists every problem, not just the first" do
      with_project(nil, rubocop: nil) do |path|
        expect(doctor(path, specs: {})).to eq(1)
        expect(out.string).to include(".conformance.yml", ".rubocop.yml", "rubocop-thread_safety")
      end
    end
  end

  describe "check" do
    let(:specs) { { "rubocop-thread_safety" => Gem::Specification.new("rubocop-thread_safety", "0.8.0") } }

    def check(path, *args) = run_cli("check", "--config", path, *args, specs: specs)

    def conformance(test_command:, setup: nil, env: nil)
      yaml = "audit:\n  require: [#{project('clean').delete_suffix('.conformance.yml')}lib/clean_project]\n"
      yaml << "  namespace: [CleanProject]\nractor:\n  test_command: #{test_command.inspect}\n"
      yaml << "  setup: #{setup.inspect}\n" if setup
      yaml << "  env:\n#{env.map { |name, value| "    #{name}: #{value.inspect}\n" }.join}" if env
      yaml
    end

    it "stops at doctor" do
      with_project(nil) do |path|
        expect(check(path)).to eq(1)
        expect(out.string).to include("check failed at doctor")
      end
    end

    it "propagates the test command's exit status, naming the stage" do
      with_project(conformance(test_command: "exit 3")) do |path|
        expect(check(path)).to eq(3)
        expect(out.string).to include("check failed at ractor.test_command", "exit 3")
      end
    end

    it "fails on a test command that cannot run" do
      with_project(conformance(test_command: "no-such-command-conformance-kit 2>/dev/null")) do |path|
        expect(check(path)).not_to eq(0)
        expect(out.string).to include("ractor.test_command")
      end
    end

    it "applies ractor.env and runs ractor.setup before the test command, in the project directory" do
      with_project(conformance(setup: "echo \"$CK_VALUE\" > setup.txt", test_command: "test -f setup.txt",
                               env: { "CK_VALUE" => "wired" })) do |path, dir|
        expect(check(path)).to eq(0), out.string
        expect(File.read(File.join(dir, "setup.txt"))).to eq("wired\n")
      end
    end

    it "stops at a failing setup" do
      with_project(conformance(setup: "exit 4", test_command: "true")) do |path|
        expect(check(path)).to eq(4)
        expect(out.string).to include("check failed at ractor.setup")
      end
    end

    it "runs the strict audit last" do
      with_project(conformance(test_command: "true")) do |path|
        expect(check(path)).to eq(0), out.string
        expect(out.string).to include("conformance-audit --strict", "check passed")
      end
    end
  end

  describe "exe/conformance-kit check" do
    def exe(*args)
      Open3.capture2e("bundle", "exec", File.join(root, "exe/conformance-kit"), *args, chdir: root)
    end

    it "exits 0 on the conforming project" do
      output, status = exe("check", "--config", project("clean"))

      expect(status.exitstatus).to eq(0), output
    end

    it "exits 1 on a mutable constant, naming it" do
      output, status = exe("check", "--config", project("mutable"))

      expect(status.exitstatus).to eq(1), output
      expect(output).to include("MutableProject::NAMES", "check failed at audit")
    end

    it "exits 1 on an unloaded autoload with strict_autoloads, and 0 without it" do
      strict, strict_status = exe("check", "--config", project("autoload"))
      lenient, lenient_status = exe("check", "--config", project("autoload", "lenient.yml"))

      expect([strict_status.exitstatus, lenient_status.exitstatus]).to eq([1, 0]), strict + lenient
      expect(strict).to include("AutoloadProject::Lazy")
    end
  end
end

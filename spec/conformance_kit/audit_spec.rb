# frozen_string_literal: true

require "conformance_kit/audit"
require "open3"
require "tmpdir"

RSpec.describe ConformanceKit::Audit do
  let(:fixture_allowlist) { File.expand_path("../fixtures/audit_allowlist.yml", __dir__) }

  def audit(namespaces: ["AuditFixture"], allowlist: ConformanceKit::Audit::Allowlist.empty)
    described_class.new(namespaces: namespaces, allowlist: allowlist)
  end

  describe "#findings" do
    subject(:findings) { audit.findings.to_h { [_1.name, _1] } }

    it "reports a Mutex in a constant" do
      expect(findings.fetch("AuditFixture::LOCK").to_s).to include("constant", "Thread::Mutex", "ConformanceKit::Store")
    end

    it "reports an unfrozen Array in a constant" do
      expect(findings.fetch("AuditFixture::NAMES").to_s).to include("Array", "not frozen")
    end

    it "reports a Proc in a module instance variable" do
      expect(findings.fetch("AuditFixture::Hooks.@on_save").to_s).to include("ivar", "Proc", "shareable_proc")
    end

    it "reports a lock in a class instance variable" do
      expect(findings).to have_key("AuditFixture::Registry.@lock")
    end

    it "leaves shareable values alone" do
      expect(findings.keys).not_to include("AuditFixture::FROZEN_NAMES", "AuditFixture::SETTINGS", "AuditFixture::Hooks.@version")
      expect(findings.keys).not_to include("AuditFixture::Hooks", "AuditFixture::Registry")
    end

    it "stays inside the namespace" do
      expect(audit(namespaces: ["AuditFixture::Hooks"]).findings.map(&:name)).to eq(["AuditFixture::Hooks.@on_save"])
    end
  end

  describe "with an allowlist" do
    it "moves allowlisted entries out of the findings" do
      allowlist = ConformanceKit::Audit::Allowlist.load(fixture_allowlist)
      result = audit(allowlist: allowlist)

      expect(result.findings).to be_empty
      expect(result.allowlisted.map(&:name)).to include("AuditFixture::Registry.@lock")
    end

    it "rejects an entry without a reason" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "allowlist.yml")
        File.write(path, "main_only:\n  - name: AuditFixture::LOCK\n")

        expect { ConformanceKit::Audit::Allowlist.load(path) }
          .to raise_error(ConformanceKit::Audit::AllowlistError, /AuditFixture::LOCK.*reason/)
      end
    end

    it "lists stale entries inside the audited namespace" do
      allowlist = ConformanceKit::Audit::Allowlist.new([{ "name" => "AuditFixture::GONE", "reason" => "removed" },
                                                        { "name" => "Elsewhere::X", "reason" => "other gem" }])

      expect(audit(allowlist: allowlist).stale).to eq(["AuditFixture::GONE"])
    end
  end

  describe ConformanceKit::Audit::CLI do
    let(:out) { StringIO.new }
    let(:err) { StringIO.new }
    let(:fixture) { File.expand_path("../fixtures/audit_fixture", __dir__) }

    def run_cli(*argv) = described_class.run(argv, out: out, err: err)

    it "exits 1 under --strict with unallowlisted findings, naming them" do
      expect(run_cli("--require", fixture, "--namespace", "AuditFixture", "--strict", "--allowlist",
                     File::NULL)).to eq(1)
      expect(out.string).to include("4 findings", "AuditFixture::LOCK", "AuditFixture::Hooks.@on_save")
    end

    it "exits 0 without --strict, reporting only" do
      expect(run_cli("--require", fixture, "--namespace", "AuditFixture", "--allowlist", File::NULL)).to eq(0)
      expect(out.string).to include("4 findings", "--strict")
    end

    it "exits 0 under --strict with the fixture allowlist" do
      expect(run_cli("--require", fixture, "--namespace", "AuditFixture", "--strict", "--allowlist",
                     fixture_allowlist)).to eq(0)
      expect(out.string).to include("0 findings", "4 allowlisted", "the fixture's registry lock")
    end

    it "exits 2 on an allowlist entry without a reason" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "allowlist.yml")
        File.write(path, "main_only:\n  - name: AuditFixture::LOCK\n")

        expect(run_cli("--require", fixture, "--namespace", "AuditFixture", "--allowlist", path)).to eq(2)
        expect(err.string).to include("reason")
      end
    end

    it "exits 2 without --namespace" do
      expect(run_cli("--require", fixture)).to eq(2)
      expect(err.string).to include("--namespace")
    end

    it "exits 2 on a namespace that is not defined" do
      expect(run_cli("--require", fixture, "--namespace", "NoSuchFixture")).to eq(2)
      expect(err.string).to include("NoSuchFixture")
    end

    it "exits 2 on a missing --allowlist file" do
      expect(run_cli("--require", fixture, "--namespace", "AuditFixture", "--allowlist", "missing.yml")).to eq(2)
      expect(err.string).to include("missing.yml")
    end

    it "reports and exits 0 on an engine without Ractor" do
      hide_const("Ractor")

      expect(run_cli("--namespace", "AuditFixture", "--strict")).to eq(0)
      expect(out.string).to include("Ractor is unavailable")
    end
  end

  describe "exe/conformance-audit" do
    let(:root) { File.expand_path("../..", __dir__) }

    def exe(*args)
      Open3.capture3("bundle", "exec", "exe/conformance-audit", *args, chdir: root)
    end

    it "exits 1 on the fixture under --strict and 0 with its allowlist" do
      _out, _err, failing = exe("--require", "./spec/fixtures/audit_fixture", "--namespace", "AuditFixture", "--strict")
      _out, _err, passing = exe("--require", "./spec/fixtures/audit_fixture", "--namespace", "AuditFixture", "--strict",
                                "--allowlist", "spec/fixtures/audit_allowlist.yml")

      expect([failing.exitstatus, passing.exitstatus]).to eq([1, 0])
    end

    it "passes the kit's own audit with its .conformance.yml" do
      out, _err, status = exe("--require", "./lib/conformance_kit", "--namespace", "ConformanceKit", "--strict")

      expect(status.exitstatus).to eq(0), out
    end
  end
end

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

    it "counts unloaded autoload constants it skipped" do
      AuditFixture::Hooks.autoload(:Lazy, "/nonexistent/audit_fixture_lazy")

      expect(audit.skipped_autoloads).to eq(["AuditFixture::Hooks::Lazy"])
    ensure
      AuditFixture::Hooks.send(:remove_const, :Lazy)
    end

    it "is not fooled by a module that overrides .constants or .instance_variables" do
      # Its own namespace: a removed stub keeps its name in ObjectSpace.
      stub_const("AuditSneakyFixture", Module.new do
        const_set(:LOCK, Mutex.new)
        instance_variable_set(:@hooks, [])
        def self.constants(*) = []
        def self.instance_variables = []
      end)

      expect(audit(namespaces: ["AuditSneakyFixture"]).findings.map(&:name))
        .to eq(["AuditSneakyFixture.@hooks", "AuditSneakyFixture::LOCK"])
    end

    it "names a BasicObject value's class instead of crashing on it" do
      # ActiveRecord parks BasicObject.new in an unresolved model's @primary_key.
      stub_const("AuditBasicObjectFixture", Class.new do
        instance_variable_set(:@primary_key, BasicObject.new)
      end)

      expect(audit(namespaces: ["AuditBasicObjectFixture"]).findings.map(&:to_s))
        .to contain_exactly(a_string_including("AuditBasicObjectFixture.@primary_key (class ivar) BasicObject"))
    end

    it "words a finding as one sentence, at the top level and nested" do
      stub_const("AuditWordingFixture", Module.new do
        const_set(:HOOK, proc { 1 })
        const_set(:HOOKS, { save: proc { 1 } })
        const_set(:LOCK, Mutex.new)
        const_set(:LOCKS, { main: Mutex.new })
      end)
      never = "never shareable: use Ractor.shareable_proc (Ruby 4.0) or Ractor.make_shareable on a capture-free proc"
      main_only = "main-only: keep per-Ractor state in ConformanceKit::Store, or allowlist it main_only"

      expect(audit(namespaces: ["AuditWordingFixture"]).findings.map(&:to_s)).to eq(
        ["AuditWordingFixture::HOOK (constant) Proc: a Proc that is #{never}",
         "AuditWordingFixture::HOOKS (constant) Hash: [:save] is a Proc that is #{never}",
         "AuditWordingFixture::LOCK (constant) Thread::Mutex: a Thread::Mutex that is #{main_only}",
         "AuditWordingFixture::LOCKS (constant) Hash: [:main] is a Thread::Mutex that is #{main_only}"]
      )
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

    describe "an ancestor: rule (framework state on the gem's subclasses)" do
      before { require_relative "../fixtures/audit_ancestor_fixture" }

      def ancestor_audit(*entries)
        audit(namespaces: ["AuditAncestorFixture"], allowlist: ConformanceKit::Audit::Allowlist.new(entries))
      end

      def rule(ancestor, ivars: nil)
        { "ancestor" => ancestor, "reason" => "the framework's own class state" }
          .merge(ivars ? { "ivars" => ivars } : {})
      end

      it "allowlists every ivar on a subclass of the ancestor, but never a constant" do
        result = ancestor_audit(rule("AuditFrameworkBase"))

        expect(result.allowlisted.map(&:name))
          .to contain_exactly("AuditAncestorFixture::Model.@columns", "AuditAncestorFixture::Model.@own_cache")
        expect(result.findings.map(&:name)).to contain_exactly("AuditAncestorFixture::Concern.@deps",
                                                               "AuditAncestorFixture::Model::TABLE")
      end

      it "keeps the gem's own state reported when ivars: names the framework's" do
        result = ancestor_audit(rule("AuditFrameworkBase", ivars: ["@columns"]))

        expect(result.allowlisted.map(&:name)).to eq(["AuditAncestorFixture::Model.@columns"])
        expect(result.findings.map(&:name)).to include("AuditAncestorFixture::Model.@own_cache")
      end

      it "matches a module extended with the ancestor" do
        expect(ancestor_audit(rule("AuditFrameworkConcern")).allowlisted.map(&:name))
          .to eq(["AuditAncestorFixture::Concern.@deps"])
      end

      it "gives the rule's reason for what it allowlisted" do
        result = ancestor_audit(rule("AuditFrameworkBase", ivars: ["@columns"]))

        expect(result.reason_for(result.allowlisted.first)).to eq("the framework's own class state")
      end

      it "prefers a name: entry's own reason over the rule's" do
        own = { "name" => "AuditAncestorFixture::Model.@own_cache", "reason" => "the model's own cache" }
        result = ancestor_audit(rule("AuditFrameworkBase"), own)

        expect(result.reason_for(result.allowlisted.find { _1.name.end_with?("@own_cache") }))
          .to eq("the model's own cache")
      end

      it "treats an ancestor that is only a declared autoload as stale, without loading it" do
        expect(ancestor_audit(rule("AuditAutoloadFramework::Base")).stale)
          .to eq(["ancestor AuditAutoloadFramework::Base"])
        expect(AuditAutoloadFramework.autoload?(:Base)).to be_truthy
      end

      it "lists a rule that matched nothing, or names no loaded constant, as stale" do
        result = ancestor_audit(rule("AuditFrameworkBase", ivars: ["@gone"]), rule("NoSuchFramework::Base"))

        expect(result.stale).to contain_exactly("ancestor AuditFrameworkBase (@gone)", "ancestor NoSuchFramework::Base")
      end
    end

    it "rejects an entry with both name: and ancestor:, or with neither" do
      [{ "name" => "A::B", "ancestor" => "C", "reason" => "r" }, { "reason" => "r" }].each do |entry|
        expect { ConformanceKit::Audit::Allowlist.new([entry]) }
          .to raise_error(ConformanceKit::Audit::AllowlistError, /name: or an ancestor:/)
      end
    end

    it "rejects ivars: that are not a non-empty list of @names" do
      [["columns"], [], "@columns"].each do |ivars|
        expect { ConformanceKit::Audit::Allowlist.new([{ "ancestor" => "C", "ivars" => ivars, "reason" => "r" }]) }
          .to raise_error(ConformanceKit::Audit::AllowlistError, /ivars: must be a non-empty list of @names/)
      end
    end

    it "rejects an ancestor that every module has" do
      %w[Object ::Module Kernel BasicObject Class].each do |core|
        expect { ConformanceKit::Audit::Allowlist.new([{ "ancestor" => core, "reason" => "r" }]) }
          .to raise_error(ConformanceKit::Audit::AllowlistError, /matches every/)
      end
    end

    it "rejects an ancestor that is not a constant path" do
      ["Object::", "::", "Foo::::Bar", "foo", "Foo Bar"].each do |path|
        expect { ConformanceKit::Audit::Allowlist.new([{ "ancestor" => path, "reason" => "r" }]) }
          .to raise_error(ConformanceKit::Audit::AllowlistError, /not a constant path/)
      end
    end

    it "accepts a constant path with Unicode identifiers" do
      expect(ConformanceKit::Audit::Allowlist.new([{ "ancestor" => "Ärger::Basis", "reason" => "r" }]).ancestor_rules
        .map(&:ancestor)).to eq(["Ärger::Basis"])
    end

    it "rejects, at audit time, an ancestor path that resolves to a module every module has" do
      allowlist = ConformanceKit::Audit::Allowlist.new([{ "ancestor" => "Object::Kernel", "reason" => "r" }])

      expect { audit(allowlist: allowlist).findings }
        .to raise_error(ConformanceKit::Audit::AllowlistError, /Object::Kernel resolves to Kernel.*every module/)
    end

    it "rejects an unknown key, so a typo cannot widen a rule" do
      expect { ConformanceKit::Audit::Allowlist.new([{ "ancestor" => "C", "ivar" => ["@x"], "reason" => "r" }]) }
        .to raise_error(ConformanceKit::Audit::AllowlistError, /unknown key ivar/)
    end

    it "rejects a blank ancestor: beside a name:" do
      expect { ConformanceKit::Audit::Allowlist.new([{ "name" => "A::B", "ancestor" => nil, "reason" => "r" }]) }
        .to raise_error(ConformanceKit::Audit::AllowlistError, /name: or an ancestor:/)
    end

    it "keeps audit.skip_autoloads to name: entries" do
      expect { ConformanceKit::Audit::Allowlist.new([{ "ancestor" => "C", "reason" => "r" }], key: "audit.skip_autoloads") }
        .to raise_error(ConformanceKit::Audit::AllowlistError, /audit.skip_autoloads.*name:/)
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

    describe "--require with a feature name instead of a path" do
      around do |example|
        $LOAD_PATH.unshift(File.dirname(fixture))
        example.run
      ensure
        $LOAD_PATH.delete(File.dirname(fixture))
      end

      it "requires it from the load path, as for an installed gem" do
        expect(run_cli("--require", "audit_fixture", "--namespace", "AuditFixture", "--allowlist", File::NULL)).to eq(0)
        expect(out.string).to include("4 findings in AuditFixture")
      end

      it "exits 2 naming a feature that cannot be loaded" do
        expect(run_cli("--require", "no_such_gem_for_the_audit", "--namespace", "AuditFixture")).to eq(2)
        expect(err.string).to include("no_such_gem_for_the_audit")
      end
    end

    it "exits 2 without --namespace and without audit.namespace, naming both" do
      expect(run_cli("--require", fixture, "--allowlist", File::NULL)).to eq(2)
      expect(err.string).to include("--namespace", ".conformance.yml audit.namespace")
    end

    describe "reading .conformance.yml" do
      def project(name, file = ".conformance.yml") = File.expand_path("../fixtures/projects/#{name}/#{file}", __dir__)

      it "audits audit.require and audit.namespace when no flags are given" do
        expect(run_cli("--config", project("mutable"), "--strict")).to eq(1)
        expect(out.string).to include("1 findings in MutableProject", "MutableProject::NAMES", "not frozen")
      end

      it "audits an audit.namespace written with a leading ::" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, ".conformance.yml")
          File.write(path, "audit:\n  require: [#{File.dirname(project('mutable'))}/lib/mutable_project]\n  " \
                           "namespace: ['::MutableProject']\n")

          expect(run_cli("--config", path, "--strict")).to eq(1)
          expect(out.string).to include("MutableProject::NAMES")
        end
      end

      it "passes the conforming project" do
        expect(run_cli("--config", project("clean"), "--strict")).to eq(0)
        expect(out.string).to include("0 findings in CleanProject")
      end

      it "lets --require and --namespace override the config" do
        expect(run_cli("--config", project("clean"), "--require", fixture, "--namespace", "AuditFixture")).to eq(0)
        expect(out.string).to include("4 findings in AuditFixture")
      end

      it "fails --strict on an unloaded autoload under strict_autoloads: true, naming it" do
        expect(run_cli("--config", project("autoload"), "--strict")).to eq(1)
        expect(out.string).to include("0 findings", "AutoloadProject::Lazy", "audit.skip_autoloads")
      end

      it "only lists the unloaded autoload without strict_autoloads" do
        expect(run_cli("--config", project("autoload", "lenient.yml"), "--strict")).to eq(0)
        expect(out.string).to include("1 unloaded autoloads skipped", "AutoloadProject::Lazy")
      end

      it "reports an unloaded autoload without failing when --strict is off" do
        expect(run_cli("--config", project("autoload"))).to eq(0)
        expect(out.string).to include("AutoloadProject::Lazy", "--strict")
      end

      it "passes an autoload listed in audit.skip_autoloads, and lists stale entries" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, ".conformance.yml")
          File.write(path, <<~YAML)
            audit:
              require: [#{File.dirname(project('autoload'))}/lib/autoload_project]
              namespace: [AutoloadProject]
              strict_autoloads: true
              skip_autoloads:
                - name: AutoloadProject::Lazy
                  reason: the fixture's optional extension
                - name: AutoloadProject::Gone
                  reason: removed
          YAML

          expect(run_cli("--config", path, "--strict")).to eq(0)
          expect(out.string).to include("the fixture's optional extension", "stale audit.skip_autoloads",
                                        "AutoloadProject::Gone")
        end
      end

      it "exits 2 on an invalid config, naming the key" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, ".conformance.yml")
          File.write(path, "audit:\n  namespace: AuditFixture\n")

          expect(run_cli("--config", path)).to eq(2)
          expect(err.string).to include(path, "audit.namespace")
        end
      end
    end

    it "exits 2 on a namespace that is not defined" do
      expect(run_cli("--require", fixture, "--namespace", "NoSuchFixture")).to eq(2)
      expect(err.string).to include("NoSuchFixture")
    end

    it "accepts a namespace written with a leading ::" do
      expect(run_cli("--require", fixture, "--namespace", "::AuditFixture", "--strict", "--allowlist",
                     File::NULL)).to eq(1)
      expect(out.string).to include("4 findings in AuditFixture")
    end

    it "exits 2 on an allowlist YAML that safe_load rejects" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "allowlist.yml")
        File.write(path, "main_only:\n  - &entry\n    name: AuditFixture::LOCK\n    reason: x\n  - *entry\n")

        expect(run_cli("--require", fixture, "--namespace", "AuditFixture", "--allowlist", path)).to eq(2)
        expect(err.string).to include(path)
      end
    end

    it "exits 2 on a namespace that is not a module" do
      expect(run_cli("--require", fixture, "--namespace", "AuditFixture::NAMES")).to eq(2)
      expect(err.string).to include("AuditFixture::NAMES", "not a module")
    end

    it "reports how many modules it audited and how many autoloads it skipped" do
      run_cli("--require", fixture, "--namespace", "AuditFixture", "--allowlist", File::NULL)

      expect(out.string).to include("3 modules audited", "0 unloaded autoloads skipped")
    end

    it "exits 2 on a missing --allowlist file" do
      expect(run_cli("--require", fixture, "--namespace", "AuditFixture", "--allowlist", "missing.yml")).to eq(2)
      expect(err.string).to include("missing.yml")
    end

    it "reports and exits 0 on an engine without Ractor" do
      status = without_ractor { run_cli("--namespace", "AuditFixture", "--strict") }

      expect(status).to eq(0)
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

    it "audits an installed gem by name outside any bundle and without a .conformance.yml" do
      Dir.mktmpdir do |dir|
        # An empty gem path: only this checkout's lib can load, never an installed conformance-kit.
        gems = { "GEM_HOME" => dir, "GEM_PATH" => dir }
        out, err, status = Bundler.with_unbundled_env do
          Open3.capture3(gems, RbConfig.ruby, File.join(root, "exe/conformance-audit"), "--require", "json",
                         "--namespace", "JSON", chdir: dir)
        end

        expect(status.exitstatus).to eq(0), err
        expect(out).to include("in JSON")
      end
    end

    it "passes the kit's own audit from its .conformance.yml alone, nothing skipped" do
      out, _err, status = exe("--strict")

      expect(status.exitstatus).to eq(0), out
      expect(out).to include("in ConformanceKit", "0 unloaded autoloads skipped")
    end
  end
end

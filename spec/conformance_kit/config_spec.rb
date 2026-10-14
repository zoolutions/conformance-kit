# frozen_string_literal: true

require "conformance_kit/config"
require "tmpdir"

RSpec.describe ConformanceKit::Config do
  def with_config(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, ".conformance.yml")
      File.write(path, yaml)
      yield path, dir
    end
  end

  def load_yaml(yaml) = with_config(yaml) { |path| described_class.load(path) }

  def error_for(yaml)
    with_config(yaml) do |path|
      expect { described_class.load(path) }.to raise_error(ConformanceKit::ConfigError) { return _1.message }
    end
  end

  describe ".load" do
    it "reads every section of the 0.2 schema" do
      config = load_yaml(<<~YAML)
        audit:
          require: [./lib/my_gem]
          namespace: [MyGem]
          strict_autoloads: true
          skip_autoloads:
            - name: MyGem::Optional
              reason: only loads with pgbus present
        ractor:
          ruby: "4.0"
          test_command: bundle exec rake test
          env:
            PGBUS_DATABASE_URL: postgres://localhost/pgbus_test
          setup: bin/conformance-db-setup
          working_directory: gem
        probes:
          gem_name: my_gem
          paths: [lib, app]
          roundhouse_app: spec/dummy
        main_only:
          - name: MyGem::LOCK
            reason: main-only
      YAML

      expect(config["audit.namespace"]).to eq(["MyGem"])
      expect(config.strict_autoloads?).to be(true)
      expect(config.skip_autoloads.reason_for("MyGem::Optional")).to eq("only loads with pgbus present")
      expect(config["ractor.test_command"]).to eq("bundle exec rake test")
      expect(config["ractor.env"]).to eq("PGBUS_DATABASE_URL" => "postgres://localhost/pgbus_test")
      expect(config["ractor.setup"]).to eq("bin/conformance-db-setup")
      expect(config["probes.paths"]).to eq(%w[lib app])
      expect(config.allowlist.names).to eq(["MyGem::LOCK"])
    end

    it "fills the defaults" do
      config = load_yaml("audit:\n  namespace: [MyGem]\n")

      expect(config["ractor.ruby"]).to eq("4.0")
      expect(config["ractor.test_command"]).to eq("bundle exec rspec --tag ractor")
      expect(config["ractor.working_directory"]).to eq(".")
      expect(config["ractor.env"]).to eq({})
      expect(config["probes.paths"]).to eq(["lib"])
      expect(config["audit.require"]).to eq([])
      expect(config.strict_autoloads?).to be(false)
      expect(config["probes.gem_name"]).to be_nil
    end

    it "resolves audit.require against the file's directory" do
      with_config("audit:\n  require: [./lib/my_gem]\n") do |path, dir|
        expect(described_class.load(path).audit_requires).to eq([File.join(dir, "lib/my_gem")])
      end
    end

    it "keeps a 0.1 file with only main_only: valid" do
      expect(load_yaml("main_only:\n  - name: MyGem::LOCK\n    reason: main-only\n").allowlist.names)
        .to eq(["MyGem::LOCK"])
    end

    it "is empty for a missing file" do
      config = described_class.load(File.join(Dir.tmpdir, "no-such-dir", ".conformance.yml"))

      expect(config.exists?).to be(false)
      expect(config["audit.namespace"]).to eq([])
      expect(config.allowlist.names).to eq([])
    end

    it "is empty for an empty file" do
      expect(load_yaml("").exists?).to be(true)
    end
  end

  describe "validation" do
    it "rejects an unknown top-level key, naming the file and the key" do
      with_config("audits:\n  namespace: [MyGem]\n") do |path|
        expect { described_class.load(path) }.to raise_error(ConformanceKit::ConfigError, /#{path}.*audits/)
      end
    end

    it "rejects an unknown key inside a section" do
      expect(error_for("ractor:\n  rubby: '4.0'\n")).to include("ractor.rubby")
    end

    it "rejects a string where a list is expected" do
      expect(error_for("audit:\n  namespace: MyGem\n")).to include("audit.namespace", "list")
    end

    it "rejects a number where a string is expected" do
      expect(error_for("ractor:\n  ruby: 4.0\n")).to include("ractor.ruby", "string", "Float")
    end

    it "rejects a non-boolean strict_autoloads" do
      expect(error_for("audit:\n  strict_autoloads: maybe\n")).to include("audit.strict_autoloads", "true or false")
    end

    it "rejects an env value that is not a string" do
      expect(error_for("ractor:\n  env:\n    PORT: 5432\n")).to include("ractor.env", "PORT")
    end

    it "rejects a section that is not a mapping" do
      expect(error_for("audit: [MyGem]\n")).to include("audit", "mapping")
    end

    it "rejects a skip_autoloads entry without a reason" do
      expect(error_for("audit:\n  skip_autoloads:\n    - name: MyGem::Optional\n"))
        .to include("MyGem::Optional", "reason")
    end

    it "rejects a main_only entry without a reason" do
      expect(error_for("main_only:\n  - name: MyGem::LOCK\n")).to include("MyGem::LOCK", "reason")
    end

    it "rejects YAML that safe_load refuses" do
      expect(error_for("audit: &a\n  namespace: [X]\nprobes: *a\n")).to include(".conformance.yml")
    end

    it "rejects a document that is not a mapping" do
      expect(error_for("- MyGem\n")).to include("mapping")
    end
  end

  describe "#[]" do
    it "raises on an unknown key" do
      expect { load_yaml("")["audit.nope"] }.to raise_error(ConformanceKit::ConfigError, /audit\.nope/)
    end
  end
end

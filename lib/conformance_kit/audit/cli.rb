# frozen_string_literal: true

require "optparse"

module ConformanceKit
  class Audit
    # `conformance-audit [--require FILE] [--namespace CONST] [--strict] [--config PATH]`
    #
    # Reads `.conformance.yml` (or `--config PATH`, alias `--allowlist`): its
    # `audit.require`/`audit.namespace` when no flags are given, its `main_only:`
    # allowlist, and `audit.strict_autoloads`/`audit.skip_autoloads`.
    #
    # Exit codes: 0 clean (or report-only, or no Ractor on this engine),
    # 1 unallowlisted findings (or, with strict_autoloads, unlisted unloaded
    # autoloads) under --strict, 2 usage or config error.
    class CLI
      DEFAULT_CONFIG = Config::DEFAULT_PATH
      DEFAULT_ALLOWLIST = DEFAULT_CONFIG
      USAGE_ERROR = 2

      def self.run(argv, out: $stdout, err: $stderr) = new(out, err).run(argv)

      def initialize(out, err)
        @out = out
        @err = err
      end

      def run(argv)
        options = parse(argv)
        return unavailable unless defined?(::Ractor)

        config = load_config(options[:config])
        namespaces = options[:namespaces].empty? ? config["audit.namespace"] : options[:namespaces]
        raise OptionParser::MissingArgument, NO_NAMESPACE if namespaces.empty?

        requires(options, config).each { require _1 }
        namespaces.each { check_namespace(_1) }
        audit = Audit.new(namespaces: namespaces, allowlist: config.allowlist, skip_autoloads: config.skip_autoloads)
        report(audit, options[:strict], config.strict_autoloads?)
      rescue OptionParser::ParseError, ConfigError, AllowlistError, LoadError, NameError, ArgumentError => e
        @err.puts "conformance-audit: #{e.message}"
        USAGE_ERROR
      end

      NO_NAMESPACE = "--namespace: nothing to audit (pass --namespace or set .conformance.yml audit.namespace)"
      private_constant :NO_NAMESPACE

      private

      def parse(argv)
        options = { requires: [], namespaces: [], strict: false, config: nil }
        parser(options).parse!(argv.dup)
        options
      end

      def parser(options)
        OptionParser.new do |o|
          o.banner = "Usage: conformance-audit [--require FILE] [--namespace CONST] [--strict] [--config PATH]"
          o.on("--require FILE", "Require FILE before auditing (repeatable; default audit.require)") do |file|
            options[:requires] << file
          end
          o.on("--namespace CONST", "Audit CONST and all under it (repeatable; default audit.namespace)") do |name|
            options[:namespaces] << name.delete_prefix("::")
          end
          o.on("--strict", "Exit 1 on any unallowlisted finding") { options[:strict] = true }
          o.on("--config PATH", "--allowlist PATH", "The config to read (default: #{DEFAULT_CONFIG})") do |path|
            options[:config] = path
          end
        end
      end

      def load_config(path)
        raise ConfigError, "config #{path} does not exist" if path && !File.exist?(path)

        Config.load(path || DEFAULT_CONFIG)
      end

      def requires(options, config)
        return config.audit_requires if options[:requires].empty?

        options[:requires].map { File.expand_path(_1) }
      end

      def check_namespace(name)
        name = name.delete_prefix("::")
        value = Object.const_get(name)
        raise ArgumentError, "namespace #{name} is a #{value.class}, not a module" unless value.is_a?(Module)
      end

      def unavailable
        @out.puts "conformance-audit: Ractor is unavailable on #{RUBY_ENGINE} #{RUBY_VERSION}; nothing to audit."
        0
      end

      def report(audit, strict, strict_autoloads)
        findings = audit.findings
        autoloads = strict_autoloads ? audit.unexpected_autoloads : []
        header(audit, findings)
        details(audit, strict_autoloads)
        return 0 if findings.empty? && autoloads.empty?
        return 1 if strict

        @out.puts "report only: --strict fails on these"
        0
      end

      def header(audit, findings)
        @out.puts "conformance-audit: #{findings.size} findings in #{audit.namespaces.join(', ')} " \
                  "(#{audit.allowlisted.size} allowlisted main-only; #{audit.modules_audited} modules audited, " \
                  "#{audit.skipped_autoloads.size} unloaded autoloads skipped)"
        findings.each { @out.puts "  #{_1}" }
      end

      def details(audit, strict_autoloads)
        allowlisted = audit.allowlisted.map { "#{_1.name} — #{audit.reason_for(_1)}" }
        section("allowlisted main-only:", allowlisted)
        section("stale allowlist entries (no longer found):", audit.stale)
        skipped = audit.skipped_autoloads - audit.unexpected_autoloads
        section("unloaded autoloads skipped by audit.skip_autoloads:",
                skipped.map { "#{_1} — #{audit.skip_autoloads.reason_for(_1)}" })
        section("stale audit.skip_autoloads entries (no longer unloaded autoloads):", audit.stale_skip_autoloads)
        section(autoload_title(strict_autoloads), audit.unexpected_autoloads)
      end

      def autoload_title(strict_autoloads)
        return "unloaded autoloads, not audited (require or eager-load them):" unless strict_autoloads

        "unloaded autoloads, not audited (strict_autoloads: eager-load them or list them in audit.skip_autoloads):"
      end

      def section(title, lines)
        return if lines.empty?

        @out.puts title
        lines.each { @out.puts "  #{_1}" }
      end
    end
  end
end

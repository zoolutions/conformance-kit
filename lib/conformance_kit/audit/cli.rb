# frozen_string_literal: true

require "optparse"

module ConformanceKit
  class Audit
    # `conformance-audit --require FILE --namespace CONST [--strict] [--allowlist PATH]`
    #
    # Exit codes: 0 clean (or report-only, or no Ractor on this engine),
    # 1 unallowlisted findings under --strict, 2 usage or allowlist error.
    class CLI
      DEFAULT_ALLOWLIST = ".conformance.yml"
      USAGE_ERROR = 2

      def self.run(argv, out: $stdout, err: $stderr) = new(out, err).run(argv)

      def initialize(out, err)
        @out = out
        @err = err
      end

      def run(argv)
        options = parse(argv)
        return unavailable unless defined?(::Ractor)

        options[:requires].each { require File.expand_path(_1) }
        options[:namespaces].each { check_namespace(_1) }
        audit = Audit.new(namespaces: options[:namespaces], allowlist: allowlist(options[:allowlist]))
        report(audit, options[:strict])
      rescue OptionParser::ParseError, AllowlistError, LoadError, NameError, ArgumentError => e
        @err.puts "conformance-audit: #{e.message}"
        USAGE_ERROR
      end

      private

      def parse(argv)
        options = { requires: [], namespaces: [], strict: false, allowlist: nil }
        parser(options).parse!(argv.dup)
        raise OptionParser::MissingArgument, "--namespace (the constant to audit)" if options[:namespaces].empty?

        options
      end

      def parser(options)
        OptionParser.new do |o|
          o.banner = "Usage: conformance-audit --require FILE --namespace CONST [--strict] [--allowlist PATH]"
          o.on("--require FILE", "Require FILE before auditing (repeatable)") { options[:requires] << _1 }
          o.on("--namespace CONST", "Audit CONST and everything under it (repeatable)") do |name|
            options[:namespaces] << name.delete_prefix("::")
          end
          o.on("--strict", "Exit 1 on any unallowlisted finding") { options[:strict] = true }
          o.on("--allowlist PATH", "main_only: allowlist (default: #{DEFAULT_ALLOWLIST} if present)") do |path|
            options[:allowlist] = path
          end
        end
      end

      def check_namespace(name)
        value = Object.const_get(name)
        raise ArgumentError, "--namespace #{name} is a #{value.class}, not a module" unless value.is_a?(Module)
      end

      def allowlist(path)
        return Allowlist.load(path) if path
        return Allowlist.load(DEFAULT_ALLOWLIST) if File.exist?(DEFAULT_ALLOWLIST)

        Allowlist.empty
      rescue Errno::ENOENT
        raise AllowlistError, "allowlist #{path} does not exist"
      end

      def unavailable
        @out.puts "conformance-audit: Ractor is unavailable on #{RUBY_ENGINE} #{RUBY_VERSION}; nothing to audit."
        0
      end

      def report(audit, strict)
        findings = audit.findings
        allowlisted = audit.allowlisted
        @out.puts "conformance-audit: #{findings.size} findings in #{audit.namespaces.join(', ')} " \
                  "(#{allowlisted.size} allowlisted main-only; #{audit.modules_audited} modules audited, " \
                  "#{audit.skipped_autoloads.size} unloaded autoloads skipped)"
        findings.each { @out.puts "  #{_1}" }
        section("allowlisted main-only:", allowlisted.map { "#{_1.name} — #{audit.allowlist.reason_for(_1.name)}" })
        section("stale allowlist entries (no longer found):", audit.stale)
        section("unloaded autoloads, not audited (require or eager-load them):", audit.skipped_autoloads)
        return 0 if findings.empty?
        return 1 if strict

        @out.puts "report only: --strict fails on these"
        0
      end

      def section(title, lines)
        return if lines.empty?

        @out.puts title
        lines.each { @out.puts "  #{_1}" }
      end
    end
  end
end

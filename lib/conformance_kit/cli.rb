# frozen_string_literal: true

require "optparse"
require_relative "../conformance_kit"
require_relative "config"
require_relative "cli/doctor"
require_relative "cli/check"
require_relative "cli/ractorize_check"

module ConformanceKit
  # `conformance-kit check|doctor|config KEY [--config PATH] [--expect X.Y] [--ractorize]`
  #
  # Exit codes: 0 ok, 1 a check failed (`check` passes on its failing stage's
  # status), 2 usage or config error.
  class CLI
    USAGE = <<~TEXT
      Usage: conformance-kit COMMAND [--config PATH]
        check [--expect X.Y]   doctor, ractor.setup, ractor.test_command, then conformance-audit --strict
        check --ractorize      ractorize.setup, then boot ractorize.app with Rails.application.ractorize!,
                               serve ractorize.requests inside non-main Ractors and audit (report-only job)
        doctor [--expect X.Y]  .conformance.yml, .rubocop.yml and the bundle are set up for the conformance workflow
        config KEY             print a .conformance.yml value (dotted key, e.g. probes.gem_name)
    TEXT
    USAGE_ERROR = 2

    def self.run(argv, out: $stdout, err: $stderr, version: VERSION, specs: Gem.loaded_specs)
      new(out: out, err: err, version: version, specs: specs).run(argv)
    end

    def initialize(out:, err:, version:, specs:)
      @out = out
      @err = err
      @version = version
      @specs = specs
    end

    def run(argv)
      command, *rest = argv
      options = parse(rest)
      dispatch(command, options)
    rescue OptionParser::ParseError, ConfigError, ArgumentError => e
      @err.puts "conformance-kit: #{e.message}"
      @err.puts USAGE
      USAGE_ERROR
    end

    private

    def dispatch(command, options)
      case command
      when "config" then print_value(options)
      when "doctor" then doctor(options).run
      when "check" then check(options)
      else raise ArgumentError, command ? "unknown command #{command}" : "no command"
      end
    end

    def parse(argv)
      options = { config: Config::DEFAULT_PATH, expect: nil, ractorize: false }
      options[:args] = OptionParser.new do |o|
        o.on("--config PATH") { options[:config] = _1 }
        o.on("--expect X.Y") { options[:expect] = expected_version(_1) }
        o.on("--ractorize") { options[:ractorize] = true }
      end.parse(argv)
      options
    end

    def expected_version(value)
      raise ArgumentError, "--expect #{value}: expected a version like 0.2" unless Gem::Version.correct?(value)

      Gem::Version.new(value)
    end

    def config(options) = Config.load(options[:config])

    def check(options)
      return RactorizeCheck.new(config(options), out: @out).run if options[:ractorize]

      Check.new(config(options), doctor(options), out: @out).run
    end

    def doctor(options)
      Doctor.new(config(options), out: @out, version: @version, specs: @specs, expect: options[:expect])
    end

    def print_value(options)
      key, *extra = options[:args]
      raise ArgumentError, "config needs a KEY (e.g. probes.gem_name)" unless key
      raise ArgumentError, "config takes one KEY, got also: #{extra.join(' ')}" if extra.any?

      @out.puts format_value(config(options)[key])
      0
    end

    def format_value(value)
      case value
      when Hash then value.map { |name, env_value| "#{name}=#{env_value}" }.join("\n")
      when Array then value.map { _1.is_a?(Hash) ? _1["name"] : _1 }.join(" ")
      else value.to_s
      end
    end
  end
end

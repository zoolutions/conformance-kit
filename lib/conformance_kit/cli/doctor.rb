# frozen_string_literal: true

require "yaml"

module ConformanceKit
  class CLI
    # The static checks the conformance workflow relies on. Every problem is
    # listed with its fix; exit 1 when there is any.
    class Doctor
      THREAD_SAFETY = "rubocop-thread_safety"
      THREAD_SAFETY_FLOOR = "0.8"
      RUBOCOP_CONFIG = "config/rubocop.yml"

      def initialize(config, out:, version:, specs:, expect: nil)
        @config = config
        @out = out
        @version = Gem::Version.new(version)
        @specs = specs
        @expect = expect
      end

      def problems
        [conformance_problem, rubocop_problem, thread_safety_problem, version_problem].compact
      end

      def run
        found = problems
        return report_ok if found.empty?

        @out.puts "conformance-kit doctor: #{found.size} problem#{'s' unless found.size == 1}"
        found.each { @out.puts "  - #{_1}" }
        1
      end

      private

      def report_ok
        @out.puts "conformance-kit doctor: ok (conformance-kit #{@version}, #{@config.source})"
        0
      end

      def conformance_problem
        unless @config.exists?
          return "no #{@config.source}: add one with audit.require and audit.namespace (see the conformance-kit README)"
        end
        return nil unless @config["audit.namespace"].empty?

        "#{@config.source} sets no audit.namespace: list the constants to audit (e.g. audit.namespace: [MyGem])"
      end

      def rubocop_problem
        path = File.join(@config.root, ".rubocop.yml")
        fix = "add `inherit_gem: { conformance-kit: #{RUBOCOP_CONFIG} }`"
        return "no #{path}: #{fix}" unless File.exist?(path)
        return nil if inherits_kit?(YAML.safe_load_file(path, aliases: true))

        "#{path} does not inherit conformance-kit's RuboCop config: #{fix}"
      rescue Psych::Exception => e
        "#{path} is not valid YAML (#{e.message})"
      end

      def inherits_kit?(rubocop)
        files = rubocop.is_a?(Hash) && rubocop.dig("inherit_gem", "conformance-kit")
        Array(files).include?(RUBOCOP_CONFIG)
      end

      def thread_safety_problem
        spec = @specs[THREAD_SAFETY]
        line = %(gem "#{THREAD_SAFETY}", ">= #{THREAD_SAFETY_FLOOR}", require: false)
        return "#{THREAD_SAFETY} is not in the bundle: add `#{line}` to the Gemfile" unless spec
        return nil if spec.version >= Gem::Version.new(THREAD_SAFETY_FLOOR)

        "#{THREAD_SAFETY} #{spec.version} is resolved: bump it to >= #{THREAD_SAFETY_FLOOR} (`#{line}`)"
      end

      def version_problem
        return nil if @expect.nil? || @version >= @expect

        segments = @expect.segments.first(2).join(".")
        "conformance-kit #{@version} is resolved, the workflow expects >= #{@expect}: " \
          "bump conformance-kit to ~> #{segments} in the Gemfile and run bundle update conformance-kit"
      end
    end
  end
end

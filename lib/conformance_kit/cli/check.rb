# frozen_string_literal: true

require "open3"
require "rbconfig"

module ConformanceKit
  class CLI
    # What the conformance workflow runs, and what a developer runs locally
    # before flipping a repo: doctor, then ractor.setup and ractor.test_command
    # (with ractor.env, in ractor.working_directory), then the strict audit.
    # Stops at the first failing stage and exits with its status.
    class Check
      AUDIT = File.expand_path("../../../exe/conformance-audit", __dir__).freeze

      def initialize(config, doctor, out:)
        @config = config
        @doctor = doctor
        @out = out
      end

      def run
        status = stages.each do |stage, command|
          code = command.call
          break failed(stage, code) unless code.zero?
        end
        return status if status.is_a?(Integer)

        @out.puts "conformance-kit check passed"
        0
      end

      private

      def stages
        list = [["doctor", -> { @doctor.run }]]
        setup = @config["ractor.setup"]
        list << ["ractor.setup", -> { shell(setup) }] if setup
        list << ["ractor.test_command", -> { shell(@config["ractor.test_command"]) }]
        list << ["audit", -> { audit }]
      end

      def shell(command)
        @out.puts "==> #{command}"
        @out.flush
        exit_code(system(@config["ractor.env"], command, chdir: @config.working_directory))
      end

      def audit
        @out.puts "==> conformance-audit --strict --config #{@config.source}"
        output, status = Open3.capture2e(@config["ractor.env"], RbConfig.ruby, AUDIT, "--strict",
                                         "--config", File.expand_path(@config.source), chdir: @config.root)
        @out.print output
        status.exitstatus || 1
      end

      # system returns nil when the command could not be spawned at all.
      def exit_code(result)
        return 127 if result.nil?

        Process.last_status.exitstatus || 1
      end

      def failed(stage, code)
        @out.puts "conformance-kit check failed at #{stage} (exit #{code})"
        code
      end
    end
  end
end

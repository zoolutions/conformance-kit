# frozen_string_literal: true

require "open3"
require "rbconfig"

module ConformanceKit
  class CLI
    # `conformance-kit check --ractorize`: what the workflow's ractorize job
    # runs. ractorize.setup in the app (RAILS_ENV=production), then the runner
    # in its own process, both with ractor.env. Stops at the first failing stage.
    class RactorizeCheck
      BOOT = File.expand_path("../ractorize/boot.rb", __dir__).freeze
      PRODUCTION = { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1" }.freeze

      def initialize(config, out:)
        @config = config
        @out = out
        @app = config.ractorize_app
        raise ConfigError, "#{config.source}: ractorize.app is not set (the Rails app to boot)" unless @app

        environment = File.join(@app, "config/environment.rb")
        return if File.file?(environment)

        raise ConfigError, "#{config.source}: ractorize.app: #{environment} does not exist"
      end

      def run
        setup = @config["ractorize.setup"]
        code = setup ? shell(setup) : 0
        return failed("ractorize.setup", code) unless code.zero?

        code = runner
        code.zero? ? code : failed("ractorize", code)
      end

      private

      def env = @config["ractor.env"].merge(PRODUCTION)

      def shell(command)
        @out.puts "==> #{command}"
        @out.flush
        # system returns nil when the command could not be spawned at all.
        return 127 if system(env, command, chdir: @app).nil?

        Process.last_status.exitstatus || 1
      end

      def runner
        @out.puts "==> ractorize #{@app}"
        @out.flush
        output, status = Open3.capture2e(env, RbConfig.ruby, BOOT, File.expand_path(@config.source), chdir: @app)
        @out.print output
        status.exitstatus || 1
      end

      def failed(stage, code)
        @out.puts "conformance-kit check failed at #{stage} (exit #{code})"
        code
      end
    end
  end
end

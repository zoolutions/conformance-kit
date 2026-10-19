# frozen_string_literal: true

require_relative "../ractorize"
require_relative "../audit"
require_relative "request"

module ConformanceKit
  module Ractorize
    # Runs in its own process (boot.rb): it boots the app, freezes it for good
    # and leaves global state behind. Boots in production with
    # `unshareable_proc_action = :raise`, calls `Rails.application.ractorize!`,
    # serves each `ractorize.requests` path inside a non-main Ractor, then audits
    # `ractorize.audit_namespaces` in the same process. Exits 0 when all of it
    # passes or the run is skipped (with the reason), 1 otherwise.
    class Runner
      def initialize(config, out:)
        @config = config
        @out = out
        @failures = 0
      end

      def run
        reason = unavailable_reason
        return skip(reason) if reason

        ActiveSupport::Ractors.unshareable_proc_action = :raise
        return 1 unless stage("boot") { boot }
        return 1 unless stage("Rails.application.ractorize!") { ractorize }

        serve_requests
        audit
        summary
      end

      private

      def unavailable_reason
        return rails_reason if Ractorize.available?

        "Ractor#value is unavailable on #{RUBY_ENGINE} #{RUBY_VERSION} (needs Ruby 4.0)"
      end

      # Checked before :raise is armed, so a Rails without ractorize! skips instead of failing its boot.
      def rails_reason
        require "rails"
        require "active_support/ractors"
        return if Rails::Application.method_defined?(:ractorize!)

        "Rails #{Rails.version} has no Rails.application.ractorize!: run it with BUNDLE_GEMFILE=Gemfile.ractorize"
      rescue LoadError => e
        return "Rails is not in the bundle: run it with BUNDLE_GEMFILE=Gemfile.ractorize" if e.path == "rails"

        "ActiveSupport::Ractors is unavailable (Rails before 8.2): run it with BUNDLE_GEMFILE=Gemfile.ractorize"
      end

      def boot
        ENV["RAILS_ENV"] = "production"
        ENV["SECRET_KEY_BASE_DUMMY"] ||= "1"
        environment = File.join(@config.ractorize_app, "config/environment.rb")
        require environment
        raise "#{environment} defined no Rails.application" unless defined?(::Rails) && ::Rails.application
      end

      def ractorize
        Warning[:experimental] = false
        Rails.application.ractorize!
        require "i18n/ractorize"
      rescue LoadError => e
        raise unless e.path == "i18n/ractorize"

        @out.puts "ractorize: note: i18n/ractorize is unavailable (released i18n): I18n reads fail in a Ractor"
      end

      def stage(name)
        yield
        @out.puts "ractorize: #{name}: ok"
        true
      rescue Exception => e # rubocop:disable Lint/RescueException -- the failure is the report
        @out.puts "ractorize: #{name} failed: #{format(Request.describe_error(e))}"
        false
      end

      def serve_requests
        @config["ractorize.requests"].each do |path|
          result = Request.serve(Rails.application, path)
          failed = result[:error] || result[:status].nil? || result[:status] >= 500
          @failures += 1 if failed
          @out.puts "  GET #{path} -> #{describe(result)}"
        end
      end

      def describe(result)
        status = result[:status] ? "#{result[:status]} (#{result[:body].bytesize} bytes)" : "raised"
        result[:error] ? "#{status}: #{format(result[:error])}" : status
      end

      def format((klass, message, frame)) = "#{klass}: #{message}\n      at #{frame}"

      def audit
        namespaces = @config.ractorize_namespaces
        return @out.puts("ractorize: audit: nothing to audit (set ractorize.audit_namespaces)") if namespaces.empty?

        missing = namespaces.reject { Object.const_defined?(_1) }
        return audit_failed("namespace #{missing.join(', ')} is not defined after boot") if missing.any?

        findings = Audit.new(namespaces: namespaces, allowlist: @config.allowlist,
                             skip_autoloads: @config.skip_autoloads).findings
        @failures += findings.size
        @out.puts "ractorize: audit #{namespaces.join(', ')} after ractorize!: #{findings.size} findings"
        findings.each { @out.puts "  #{_1}" }
      end

      def audit_failed(message)
        @failures += 1
        @out.puts "ractorize: audit failed: #{message}"
      end

      def summary
        return 0.tap { @out.puts "ractorize passed" } if @failures.zero?

        @out.puts "ractorize failed: #{@failures} failures (failed requests and audit findings)"
        1
      end

      def skip(reason)
        @out.puts "ractorize: skipped: #{reason}"
        0
      end
    end
  end
end

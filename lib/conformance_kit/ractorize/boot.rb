# frozen_string_literal: true

# The ractorize job's process: `ruby boot.rb .conformance.yml`, under the
# bundle that has Rails (BUNDLE_GEMFILE=Gemfile.ractorize). conformance-kit
# check --ractorize starts it; it never runs inside the kit's own process.
require_relative "runner"

$stdout.sync = true
exit ConformanceKit::Ractorize::Runner.new(ConformanceKit::Config.load(ARGV.fetch(0)), out: $stdout).run

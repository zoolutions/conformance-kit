# frozen_string_literal: true

require_relative "lib/conformance_kit/version"

Gem::Specification.new do |spec|
  spec.name = "conformance-kit"
  spec.version = ConformanceKit::VERSION
  spec.authors = ["mhenrixon"]
  spec.email = ["mikael@mhenrixon.com"]

  spec.summary = "Concurrency conformance gates for Ruby gems: threads, fibers, Ractors and compiler probes."
  spec.description = "Shared RSpec examples, a per-Ractor storage shim, a class-state audit, " \
                     "RuboCop configs and a reusable CI workflow that hold a gem to explicit " \
                     "thread-safe, fiber-safe and Ractor-clean tiers."
  spec.homepage = "https://github.com/zoolutions/conformance-kit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "exe/*", "config/**/*", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  spec.bindir = "exe"
  spec.executables = Dir["exe/*"].map { File.basename(_1) }
  spec.require_paths = ["lib"]
end

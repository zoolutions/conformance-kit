# frozen_string_literal: true

require "bundler"
require "fileutils"
require "tmpdir"

RSpec.describe "config/ractorize.gemfile" do
  let(:ractorize_gemfile) { File.expand_path("../../config/ractorize.gemfile", __dir__) }

  # The dependencies Bundler reads from Gemfile.ractorize next to +repo_gemfile+ (no resolve, no network).
  def dependencies(repo_gemfile, gemspec: nil)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Gemfile"), repo_gemfile)
      File.write(File.join(dir, "my_gem.gemspec"), gemspec) if gemspec
      FileUtils.cp(ractorize_gemfile, File.join(dir, "Gemfile.ractorize"))
      Bundler::Dsl.evaluate(File.join(dir, "Gemfile.ractorize"), File.join(dir, "Gemfile.ractorize.lock"), {})
                  .dependencies.to_h { [_1.name, _1.source] }
    end
  end

  def github(source) = [source.uri, source.options["branch"] || source.options["ref"]]

  it "drops the repo's own rails, rack and Rails component lines and declares the branches" do
    sources = dependencies(<<~RUBY)
      source "https://rubygems.org"
      gem "rails", "~> 8.0"
      gem "activerecord", "~> 8.0"
      gem "rack", "~> 3.1"
      gem "rake"
    RUBY

    expect(sources.keys).to contain_exactly("rails", "rack", "i18n", "rake")
    expect(github(sources.fetch("rails"))).to eq(["https://github.com/rails/rails.git", "main"])
    expect(github(sources.fetch("rack"))).to eq(["https://github.com/rack/rack.git", "main"])
    expect(github(sources.fetch("i18n"))).to eq(["https://github.com/Shopify/i18n.git", "refs/pull/5/head"])
    expect(sources.fetch("rake")).to be_nil
  end

  it "drops the gemspec's development dependencies on them too" do
    gemspec = <<~RUBY
      Gem::Specification.new do |spec|
        spec.name = "my_gem"
        spec.version = "0.1.0"
        spec.summary = "fixture"
        spec.authors = ["fixture"]
        spec.files = []
        spec.add_dependency "railties", ">= 7.1"
        spec.add_development_dependency "rack", "~> 3.1"
      end
    RUBY

    sources = dependencies(%(source "https://rubygems.org"\ngemspec\n), gemspec: gemspec)

    expect(sources.keys).to contain_exactly("my_gem", "rails", "rack", "i18n")
    expect(github(sources.fetch("rack"))).to eq(["https://github.com/rack/rack.git", "main"])
  end
end

# frozen_string_literal: true

require "yaml"
require_relative "audit/allowlist"

module ConformanceKit
  class ConfigError < StandardError; end

  # A repo's `.conformance.yml`: what `conformance-kit check` and
  # `conformance-audit` hold it to. Every key is validated; a missing file is
  # an empty config. Paths in it are relative to the file.
  #
  #   audit:    { require: [], namespace: [], strict_autoloads: false, skip_autoloads: [] }
  #   ractor:   { ruby: "4.0", test_command: "...", env: {}, setup: nil, working_directory: "." }
  #   probes:   { gem_name: nil, paths: [lib], roundhouse_app: nil }
  #   main_only: []
  class Config
    DEFAULT_PATH = ".conformance.yml"

    TYPES = {
      "audit.require" => :list,
      "audit.namespace" => :list,
      "audit.strict_autoloads" => :boolean,
      "audit.skip_autoloads" => :entries,
      "ractor.ruby" => :string,
      "ractor.test_command" => :string,
      "ractor.env" => :string_map,
      "ractor.setup" => :string,
      "ractor.working_directory" => :string,
      "probes.gem_name" => :string,
      "probes.paths" => :list,
      "probes.roundhouse_app" => :string,
      "main_only" => :entries
    }.freeze

    DEFAULTS = {
      "audit.require" => [].freeze,
      "audit.namespace" => [].freeze,
      "audit.strict_autoloads" => false,
      "audit.skip_autoloads" => [].freeze,
      "ractor.ruby" => "4.0",
      "ractor.test_command" => "bundle exec rspec --tag ractor",
      "ractor.env" => {}.freeze,
      "ractor.working_directory" => ".",
      "probes.paths" => ["lib"].freeze,
      "main_only" => [].freeze
    }.freeze

    SECTIONS = %w[audit ractor probes].freeze

    def self.load(path = DEFAULT_PATH)
      root = File.dirname(File.expand_path(path))
      return new({}, source: path, root: root, exists: false) unless File.exist?(path)

      new(YAML.safe_load_file(path) || {}, source: path, root: root, exists: true)
    rescue Psych::Exception => e
      raise ConfigError, "#{path}: #{e.message}"
    end

    attr_reader :source, :root, :allowlist, :skip_autoloads

    def initialize(data, source:, root:, exists: true)
      @source = source
      @root = root
      @exists = exists
      raise ConfigError, "#{source}: expected a mapping (audit:, ractor:, probes:, main_only:)" unless data.is_a?(Hash)

      @values = flatten(data).to_h { |key, value| [key, validate(key, value)] }
      @allowlist = entries("main_only")
      @skip_autoloads = entries("audit.skip_autoloads")
    end

    def exists? = @exists

    # A dotted key (`ractor.ruby`): its value, or its default (nil when it has none).
    def [](key)
      unknown_key!(key, TYPES.keys) unless TYPES.key?(key)

      @values.fetch(key) { DEFAULTS[key] }
    end

    def audit_requires = self["audit.require"].map { File.expand_path(_1, root) }
    def strict_autoloads? = self["audit.strict_autoloads"]
    def working_directory = File.expand_path(self["ractor.working_directory"], root)

    private

    def flatten(data)
      data.flat_map do |key, value|
        next [[key, value]] if key == "main_only"

        unknown_key!(key, [*SECTIONS, "main_only"]) unless SECTIONS.include?(key)
        next [] if value.nil?
        raise ConfigError, "#{source}: #{key}: must be a mapping, got #{value.class}" unless value.is_a?(Hash)

        value.map { |sub, sub_value| ["#{key}.#{sub}", sub_value] }
      end
    end

    def validate(key, value)
      type = TYPES.fetch(key) { unknown_key!(key, TYPES.keys) }
      return value if value.nil? || valid?(type, value)

      raise ConfigError, "#{source}: #{key} must be #{EXPECTED.fetch(type)}, got #{value.class} #{value.inspect}"
    end

    EXPECTED = {
      list: "a list of strings",
      string: "a string (quote it)",
      boolean: "true or false",
      string_map: "a mapping of names to string values (quote numbers)",
      entries: "a list of name:/reason: entries"
    }.freeze
    private_constant :EXPECTED

    def valid?(type, value)
      case type
      when :list then value.is_a?(Array) && value.all?(String)
      when :string then value.is_a?(String)
      when :boolean then [true, false].include?(value)
      when :string_map then value.is_a?(Hash) && value.all? { |k, v| k.is_a?(String) && v.is_a?(String) }
      when :entries then value.is_a?(Array)
      end
    end

    def unknown_key!(key, known)
      raise ConfigError, "#{source}: unknown key #{key} (one of #{known.join(', ')})"
    end

    def entries(key)
      Audit::Allowlist.new(self[key] || [], source: source, key: key)
    rescue Audit::AllowlistError => e
      raise ConfigError, e.message
    end
  end
end

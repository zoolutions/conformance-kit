# frozen_string_literal: true

require "yaml"
require_relative "ancestor_rule"

module ConformanceKit
  class Audit
    class AllowlistError < StandardError; end

    # `.conformance.yml`: state that is deliberately main-only, each entry with
    # the reason it is safe.
    #
    #   main_only:
    #     - name: MyGem::Registry.@lock      # a class/module ivar: Owner.@ivar
    #       reason: guards boot-time registration; never touched by a non-main Ractor
    #     - name: MyGem::LOCK                # a constant: Owner::NAME
    #       reason: ...
    #     - ancestor: Rails::Engine          # framework state on the gem's subclasses
    #       reason: ...                      # (see AncestorRule)
    #
    # `audit.skip_autoloads:` entries have the name:/reason: shape (`key:` names the list).
    class Allowlist
      def self.empty = new([])

      def self.load(path)
        data = YAML.safe_load_file(path) || {}
        raise AllowlistError, "#{path}: expected a mapping with a main_only: list" unless data.is_a?(Hash)

        new(data.fetch("main_only", []) || [], source: path)
      rescue Psych::Exception => e
        raise AllowlistError, "#{path}: #{e.message}"
      end

      attr_reader :entries, :ancestor_rules

      def initialize(entries, source: "the allowlist", key: "main_only")
        @key = key
        raise AllowlistError, "#{source}: #{key}: must be a list" unless entries.is_a?(Array)

        @entries = entries.map { validate(_1, source) }
        @ancestor_rules = @entries.select { _1.key?("ancestor") }.map { AncestorRule.new(_1) }.freeze
      end

      def names = entries.filter_map { _1["name"] }
      def include?(name) = names.include?(name)
      def reason_for(name) = entries.find { _1["name"] == name }&.fetch("reason")

      # The first ancestor: rule covering +ivar+ on +mod+, or nil.
      def rule_for(mod, ivar) = ancestor_rules.find { _1.match?(mod, ivar) }

      private

      def validate(entry, source)
        unless entry.is_a?(Hash)
          raise AllowlistError,
                "#{source}: each #{@key} entry needs a name: and a reason:, got #{entry.inspect}"
        end

        label = validate_target(entry, source)
        raise AllowlistError, "#{source}: #{label} has no reason: (say why it is safe)" if blank?(entry["reason"])

        entry
      end

      # An entry names one constant or ivar (name:), or, in main_only, a
      # framework ancestor (ancestor:, optional ivars:). Returns its label.
      def validate_target(entry, source)
        name, ancestor = entry.values_at("name", "ancestor")
        if blank?(name) == blank?(ancestor)
          raise AllowlistError, "#{source}: each #{@key} entry needs a name: or an ancestor: (#{entry.inspect})"
        end
        return name if blank?(ancestor)

        validate_ancestor(entry, ancestor, source)
        "ancestor #{ancestor}"
      end

      def validate_ancestor(entry, ancestor, source)
        unless @key == "main_only"
          raise AllowlistError, "#{source}: #{@key} entries take a name:, not an ancestor: (#{ancestor})"
        end

        ivars = entry.fetch("ivars", [])
        return if ivars.is_a?(Array) && ivars.all? { _1.is_a?(String) && _1.match?(/\A@\w+\z/) }

        raise AllowlistError, "#{source}: ancestor #{ancestor}: ivars: must be a list of @names, got #{ivars.inspect}"
      end

      def blank?(value) = !value.is_a?(String) || value.strip.empty?
    end
  end
end

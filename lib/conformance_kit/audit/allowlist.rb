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

      # Ancestors every module has: a rule naming one would cover every ivar.
      EVERY_MODULE = %w[BasicObject Object Kernel Module Class].freeze

      private

      def validate(entry, source)
        unless entry.is_a?(Hash)
          raise AllowlistError,
                "#{source}: each #{@key} entry needs a name: (or, in main_only, an ancestor:) and a reason:, " \
                "got #{entry.inspect}"
        end

        validate_keys(entry, source)
        label = validate_target(entry, source)
        raise AllowlistError, "#{source}: #{label} has no reason: (say why it is safe)" if blank?(entry["reason"])

        entry
      end

      # Every key is known, so a typo (ivar: for ivars:) cannot quietly widen a rule.
      def validate_keys(entry, source)
        if @key != "main_only" && entry.key?("ancestor")
          raise AllowlistError, "#{source}: #{@key} entries take a name:, not an ancestor: (#{entry['ancestor']})"
        end

        known = @key == "main_only" ? %w[name ancestor ivars reason] : %w[name reason]
        unknown = entry.keys - known
        return if unknown.empty?

        raise AllowlistError, "#{source}: a #{@key} entry has an unknown key #{unknown.first} " \
                              "(one of #{known.join(', ')}): #{entry.inspect}"
      end

      # An entry names one constant or ivar (name:), or, in main_only, a
      # framework ancestor (ancestor:, optional ivars:). Returns its label.
      def validate_target(entry, source)
        targets = %w[name ancestor].select { entry.key?(_1) }
        unless targets.size == 1
          raise AllowlistError, "#{source}: each #{@key} entry needs a name: or an ancestor:, not both " \
                                "(#{entry.inspect})"
        end

        key = targets.first
        raise AllowlistError, "#{source}: a #{@key} entry has a blank #{key}: (#{entry.inspect})" if blank?(entry[key])
        return validate_name(entry, source) if key == "name"

        validate_ancestor(entry, entry["ancestor"], source)
        "ancestor #{entry['ancestor']}"
      end

      def validate_name(entry, source)
        return entry["name"] unless entry.key?("ivars")

        raise AllowlistError, "#{source}: #{entry['name']}: ivars: only goes with an ancestor:"
      end

      CONSTANT_PATH = /\A(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*\z/
      private_constant :CONSTANT_PATH

      def validate_ancestor(entry, ancestor, source)
        unless ancestor.match?(CONSTANT_PATH)
          raise AllowlistError, "#{source}: ancestor #{ancestor.inspect} is not a constant path (e.g. Rails::Engine)"
        end
        if EVERY_MODULE.include?(ancestor.delete_prefix("::"))
          raise AllowlistError, "#{source}: ancestor #{ancestor} matches every module: name the framework's own class"
        end
        return unless entry.key?("ivars")

        ivars = entry["ivars"]
        return if ivars.is_a?(Array) && !ivars.empty? && ivars.all? { _1.is_a?(String) && _1.match?(/\A@\w+\z/) }

        raise AllowlistError,
              "#{source}: ancestor #{ancestor}: ivars: must be a non-empty list of @names, got #{ivars.inspect}"
      end

      def blank?(value) = !value.is_a?(String) || value.strip.empty?
    end
  end
end

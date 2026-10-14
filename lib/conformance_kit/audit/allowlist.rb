# frozen_string_literal: true

require "yaml"

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
    class Allowlist
      def self.empty = new([])

      def self.load(path)
        data = YAML.safe_load_file(path) || {}
        raise AllowlistError, "#{path}: expected a mapping with a main_only: list" unless data.is_a?(Hash)

        new(data.fetch("main_only", []) || [], source: path)
      rescue Psych::Exception => e
        raise AllowlistError, "#{path}: #{e.message}"
      end

      attr_reader :entries

      def initialize(entries, source: "the allowlist")
        raise AllowlistError, "#{source}: main_only: must be a list" unless entries.is_a?(Array)

        @entries = entries.map { validate(_1, source) }
      end

      def names = entries.map { _1["name"] }
      def include?(name) = names.include?(name)
      def reason_for(name) = entries.find { _1["name"] == name }&.fetch("reason")

      private

      def validate(entry, source)
        unless entry.is_a?(Hash)
          raise AllowlistError,
                "#{source}: each main_only entry needs a name: and a reason:, got #{entry.inspect}"
        end

        name = entry["name"]
        raise AllowlistError, "#{source}: a main_only entry has no name: (#{entry.inspect})" if blank?(name)
        if blank?(entry["reason"])
          raise AllowlistError,
                "#{source}: #{name} has no reason: (say why it is safe main-only)"
        end

        entry
      end

      def blank?(value) = !value.is_a?(String) || value.strip.empty?
    end
  end
end

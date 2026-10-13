# frozen_string_literal: true

require "conformance_kit"
require_relative "audit/allowlist"
require_relative "audit/cli"

module ConformanceKit
  # Walks every loaded module under the given namespaces and reports each
  # constant and class/module instance variable whose value is not
  # Ractor-shareable. Unloaded autoload constants are skipped: require (or
  # eager-load) everything the audit should see.
  class Audit
    Finding = Data.define(:name, :kind, :value_class, :path, :reason) do
      def to_s
        where = path.empty? ? "" : " #{path} is"
        "#{name} (#{kind}) #{value_class}:#{where} #{reason}"
      end
    end

    attr_reader :namespaces, :allowlist

    def initialize(namespaces:, allowlist: Allowlist.empty)
      @namespaces = namespaces
      @allowlist = allowlist
    end

    def findings = partitioned.first
    def allowlisted = partitioned.last

    # Allowlisted names inside the audited namespaces that no longer turn up.
    def stale
      found = scan.map(&:name)
      @allowlist.names.select { in_namespace?(_1) && !found.include?(_1) }
    end

    private

    def partitioned
      @partitioned ||= scan.partition { !@allowlist.include?(_1.name) }
    end

    def scan
      @scan ||= audited_modules.flat_map { |mod, name| constant_findings(mod, name) + ivar_findings(mod, name) }
                               .sort_by(&:name)
    end

    def audited_modules
      ObjectSpace.each_object(Module).filter_map do |mod|
        next if mod.singleton_class?

        name = ::Module.instance_method(:name).bind_call(mod) # a class may override .name
        [mod, name] if name && in_namespace?(name)
      end
    end

    def in_namespace?(name)
      namespaces.any? { |namespace| name == namespace || name.start_with?("#{namespace}::", "#{namespace}.") }
    end

    def constant_findings(mod, name)
      mod.constants(false).filter_map do |constant|
        next if mod.autoload?(constant)

        finding("#{name}::#{constant}", "constant", mod.const_get(constant, false))
      end
    end

    def ivar_findings(mod, name)
      mod.instance_variables.filter_map do |ivar|
        finding("#{name}.#{ivar}", mod.is_a?(Class) ? "class ivar" : "module ivar", mod.instance_variable_get(ivar))
      end
    end

    def finding(name, kind, value)
      culprit = Shareability.culprit(value)
      return nil unless culprit

      Finding.new(name: name, kind: kind, value_class: value.class.name, path: culprit.path, reason: culprit.reason)
    end
  end
end

# frozen_string_literal: true

require "conformance_kit"
require_relative "config"
require_relative "audit/allowlist"
require_relative "audit/cli"

module ConformanceKit
  # Walks every loaded module under the given namespaces and reports each
  # constant and class/module instance variable whose value is not
  # Ractor-shareable. Unloaded autoload constants are skipped: require (or
  # eager-load) everything the audit should see, and list deliberate exceptions
  # in `skip_autoloads` (`audit.skip_autoloads:` in .conformance.yml).
  class Audit
    # +rule+: the main_only ancestor: rule that covers it, or nil.
    Finding = Data.define(:name, :kind, :value_class, :path, :reason, :rule) do
      def to_s
        where = path.empty? ? "" : " #{path} is"
        "#{name} (#{kind}) #{value_class}:#{where} #{reason}"
      end
    end

    attr_reader :namespaces, :allowlist, :skip_autoloads

    def initialize(namespaces:, allowlist: Allowlist.empty, skip_autoloads: Allowlist.empty)
      @namespaces = namespaces
      @allowlist = allowlist
      @skip_autoloads = skip_autoloads
    end

    def findings = partitioned.first
    def allowlisted = partitioned.last

    def modules_audited = audited_modules.size

    # Constants declared with `autoload` but never loaded: not audited.
    def skipped_autoloads
      @skipped_autoloads ||= audited_modules.flat_map do |mod, name|
        constants_of(mod).select { autoload?(mod, _1) }.map { "#{name}::#{_1}" }
      end
    end

    # Skipped autoloads not listed in skip_autoloads: what strict_autoloads fails on.
    def unexpected_autoloads = skipped_autoloads - @skip_autoloads.names

    # Why an allowlisted finding is main-only: its own name: entry's reason, else its ancestor: rule's.
    def reason_for(finding) = @allowlist.reason_for(finding.name) || finding.rule&.reason

    # Allowlisted names inside the audited namespaces that no longer turn up,
    # and ancestor: rules that covered nothing.
    def stale
      found = scan.map(&:name)
      used = scan.filter_map(&:rule)
      @allowlist.names.select { in_namespace?(_1) && !found.include?(_1) } +
        @allowlist.ancestor_rules.reject { |rule| used.any? { _1.equal?(rule) } }.map(&:label)
    end

    # skip_autoloads names inside the audited namespaces that are no longer unloaded autoloads.
    def stale_skip_autoloads
      skipped = skipped_autoloads
      @skip_autoloads.names.select { in_namespace?(_1) && !skipped.include?(_1) }
    end

    private

    def partitioned
      @partitioned ||= scan.partition { !_1.rule && !@allowlist.include?(_1.name) }
    end

    def scan
      @scan ||= audited_modules.flat_map { |mod, name| constant_findings(mod, name) + ivar_findings(mod, name) }
                               .sort_by(&:name)
    end

    def audited_modules
      @audited_modules ||= ObjectSpace.each_object(Module).filter_map do |mod|
        next if mod.singleton_class?

        name = ::Module.instance_method(:name).bind_call(mod) # a class may override .name
        [mod, name] if name && in_namespace?(name)
      end
    end

    def in_namespace?(name)
      namespaces.any? { |namespace| name == namespace || name.start_with?("#{namespace}::", "#{namespace}.") }
    end

    def constant_findings(mod, name)
      constants_of(mod).filter_map do |constant|
        next if autoload?(mod, constant)

        finding("#{name}::#{constant}", "constant", core(::Module, :const_get, mod, constant, false), nil)
      end
    end

    def ivar_findings(mod, name)
      core(::Kernel, :instance_variables, mod).filter_map do |ivar|
        kind = mod.is_a?(Class) ? "class ivar" : "module ivar"
        finding("#{name}.#{ivar}", kind, core(::Kernel, :instance_variable_get, mod, ivar), mod, ivar)
      end
    end

    # The core reflection methods, bound directly: a module may override its own
    # `.constants` or `.instance_variables` and hide state from the audit.
    def core(owner, method, receiver, *) = owner.instance_method(method).bind_call(receiver, *)
    def constants_of(mod) = core(::Module, :constants, mod, false)
    def autoload?(mod, constant) = core(::Module, :autoload?, mod, constant)

    # +mod+ and +ivar+ (an ivar finding only) are what an ancestor: rule matches on.
    def finding(name, kind, value, mod, ivar = nil)
      culprit = Shareability.culprit(value)
      return nil unless culprit

      Finding.new(name: name, kind: kind, value_class: core(::Kernel, :class, value).name, path: culprit.path,
                  reason: culprit.reason, rule: ivar && rule_for(mod, ivar))
    end

    # The first ancestor: rule covering +ivar+ on +mod+, or nil.
    def rule_for(mod, ivar) = rule_targets.find { |rule, target| target && rule.covers?(mod, ivar, target) }&.first

    # Each ancestor: rule with the module it names, resolved once, after audit.require.
    def rule_targets = @rule_targets ||= @allowlist.ancestor_rules.map { [_1, _1.resolve] }
  end
end

# frozen_string_literal: true

module ConformanceKit
  class Audit
    # A `main_only:` entry that names a framework class or module instead of
    # one ivar: every class/module ivar (or only the listed `ivars:`) on a
    # module that inherits from, includes or is extended with `ancestor` is
    # main-only, for one reason. Constants are never covered: they are the
    # gem's own.
    #
    #   main_only:
    #     - ancestor: ActiveRecord::Base
    #       ivars: ["@primary_key"]      # optional; omit to cover every ivar
    #       reason: ActiveRecord's own class state, set by Rails at boot on the main Ractor
    class AncestorRule
      attr_reader :ancestor, :ivars, :reason

      def initialize(entry)
        @ancestor = entry.fetch("ancestor").delete_prefix("::")
        @ivars = entry["ivars"]&.dup&.freeze
        @reason = entry.fetch("reason")
        freeze
      end

      def label = ivars ? "ancestor #{ancestor} (#{ivars.join(', ')})" : "ancestor #{ancestor}"

      # The loaded module +ancestor+ names, or nil when it isn't loaded: not
      # defined, or only a declared autoload (never loaded here: loading it
      # mid-audit would change what is being audited). A nil rule covers
      # nothing and is listed as stale. Called once per audit, after audit.require.
      def resolve
        ancestor.split("::").reduce(Object) do |scope, segment|
          return nil unless core(::Module, :const_defined?, scope, segment, false)
          return nil if core(::Module, :autoload?, scope, segment, false)

          value = core(::Module, :const_get, scope, segment, false)
          return nil unless ::Module === value # rubocop:disable Style/CaseEquality -- a BasicObject has no is_a?

          value
        end
      end

      # Whether this rule covers +ivar+ on +mod+, given its resolved +target+.
      def covers?(mod, ivar, target)
        return false if ivars && !ivars.include?(ivar.to_s)
        return false if target.equal?(mod)

        [mod, core(::Kernel, :singleton_class, mod)].any? do |owner|
          core(::Module, :ancestors, owner).any? { _1.equal?(target) }
        end
      end

      private

      # The core reflection methods, bound directly, as in Audit.
      def core(owner, method, receiver, *) = owner.instance_method(method).bind_call(receiver, *)
    end
  end
end

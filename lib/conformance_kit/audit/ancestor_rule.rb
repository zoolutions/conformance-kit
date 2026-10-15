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

      def match?(mod, ivar)
        return false if ivars && !ivars.include?(ivar.to_s)

        target = resolve
        return false unless target && !target.equal?(mod)

        ancestors_of(mod).include?(target) || ancestors_of(singleton_of(mod)).include?(target)
      end

      private

      # Unloaded (the framework isn't in this bundle): the rule matches nothing
      # and the audit lists it as stale.
      def resolve
        value = Object.const_get(ancestor)
        value if value.is_a?(Module)
      rescue NameError
        nil
      end

      def ancestors_of(mod) = ::Module.instance_method(:ancestors).bind_call(mod)
      def singleton_of(mod) = ::Kernel.instance_method(:singleton_class).bind_call(mod)
    end
  end
end

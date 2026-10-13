# frozen_string_literal: true

module ConformanceKit
  # Finds WHY a value is not Ractor-shareable: the deepest offending object,
  # the path to it, and the fix.
  module Shareability
    Culprit = Data.define(:path, :object_class, :reason)

    LOCKS = %w[Thread::Mutex Monitor Thread::Queue Thread::SizedQueue Thread::ConditionVariable].freeze
    MAX_DEPTH = 32

    class << self
      def available? = defined?(::Ractor) ? ::Ractor.respond_to?(:shareable?) : false

      # nil when the value is shareable, a Culprit otherwise.
      def culprit(value)
        return nil if ::Ractor.shareable?(value)

        find(value, "", {}, 0)
      end

      private

      def find(value, path, seen, depth)
        return nil if ::Ractor.shareable?(value) || seen.key?(value.__id__)
        return blame(value, path) if leaf?(value) || depth >= MAX_DEPTH

        seen[value.__id__] = true
        children(value).each do |child_path, child|
          found = find(child, path + child_path, seen, depth + 1)
          return found if found
        end
        blame(value, path)
      end

      def leaf?(value)
        value.is_a?(::Proc) || value.is_a?(::Method) || lock?(value) || concurrent?(value) || !value.frozen?
      end

      def children(value)
        pairs = value.instance_variables.map { |ivar| [".#{ivar}", value.instance_variable_get(ivar)] }
        case value
        when ::Hash then pairs + value.flat_map { |k, v| [["{key #{k.inspect}}", k], ["[#{k.inspect}]", v]] }
        when ::Array then pairs + value.each_with_index.map { |v, i| ["[#{i}]", v] }
        when ::Struct, ::Data then pairs + value.to_h.map { |k, v| [".#{k}", v] }
        when ::Range then pairs + [[".begin", value.begin], [".end", value.end]]
        else pairs
        end
      end

      def blame(value, path)
        Culprit.new(path: path, object_class: class_name(value), reason: reason(value))
      end

      def reason(value)
        name = class_name(value)
        if value.is_a?(::Proc) || value.is_a?(::Method)
          "a #{name} is never shareable: use Ractor.shareable_proc (Ruby 4.0) " \
            "or Ractor.make_shareable on a capture-free proc"
        elsif lock?(value) || concurrent?(value)
          "a #{name} is main-only: keep per-Ractor state in ConformanceKit::Store, or allowlist it main_only"
        elsif !value.frozen?
          "a #{name} that is not frozen: freeze it at boot (Ractor.make_shareable)"
        else
          "a #{name} that is frozen but not shareable (an extension object, or unshareable internals)"
        end
      end

      def lock?(value) = LOCKS.include?(class_name(value))
      def concurrent?(value) = class_name(value).start_with?("Concurrent::")
      def class_name(value) = ::Kernel.instance_method(:class).bind_call(value).name || "anonymous class"
    end
  end
end

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
        return blame(value, path) if intrinsic?(value) || depth >= MAX_DEPTH

        seen[value.__id__] = true
        # Freezing an unfrozen container would not fix a lock or a Proc inside it.
        return intrinsic_below(value, path, seen, depth) || blame(value, path) unless value.frozen?

        children(value).each do |child_path, child|
          found = find(child, path + child_path, seen, depth + 1)
          return found if found
        end
        blame(value, path)
      end

      def intrinsic?(value) = callable?(value) || lock?(value) || concurrent?(value)

      # The first never-shareable object (lock, Proc, Concurrent::*) under value.
      def intrinsic_below(value, path, seen, depth)
        return nil if depth >= MAX_DEPTH

        children(value).each do |child_path, child|
          next if ::Ractor.shareable?(child) || seen.key?(child.__id__)
          return blame(child, path + child_path) if intrinsic?(child)

          seen[child.__id__] = true
          found = intrinsic_below(child, path + child_path, seen, depth + 1)
          return found if found
        end
        nil
      end

      def children(value)
        pairs = value.instance_variables.map { |ivar| [".#{ivar}", value.instance_variable_get(ivar)] }
        case value
        when ::Hash then pairs + hash_children(value)
        when ::Array then pairs + value.each_with_index.map { |v, i| ["[#{i}]", v] }
        when ::Struct, ::Data then pairs + value.to_h.map { |k, v| [".#{k}", v] }
        when ::Range then pairs + [[".begin", value.begin], [".end", value.end]]
        else pairs
        end
      end

      def hash_children(hash)
        pairs = hash.flat_map { |k, v| [["{key #{k.inspect}}", k], ["[#{k.inspect}]", v]] }
        hash.default_proc ? pairs + [[".default_proc", hash.default_proc]] : pairs
      end

      def blame(value, path)
        Culprit.new(path: path, object_class: class_name(value), reason: reason(value))
      end

      def reason(value)
        name = class_name(value)
        if callable?(value)
          "#{article(name)} #{name} is never shareable: use Ractor.shareable_proc (Ruby 4.0) " \
            "or Ractor.make_shareable on a capture-free proc"
        elsif lock?(value) || concurrent?(value)
          "#{article(name)} #{name} is main-only: keep per-Ractor state in ConformanceKit::Store, " \
            "or allowlist it main_only"
        elsif !value.frozen?
          "#{article(name)} #{name} that is not frozen: freeze it at boot (Ractor.make_shareable)"
        else
          "#{article(name)} #{name} that is frozen but not shareable (an extension object, or unshareable internals)"
        end
      end

      def article(name) = name.match?(/\A[AEIOU]/) ? "an" : "a"
      def callable?(value) = value.is_a?(::Proc) || value.is_a?(::Method) || value.is_a?(::UnboundMethod)
      def lock?(value) = LOCKS.include?(class_name(value))
      def concurrent?(value) = class_name(value).start_with?("Concurrent::")
      def class_name(value) = ::Kernel.instance_method(:class).bind_call(value).name || "anonymous class"
    end
  end
end

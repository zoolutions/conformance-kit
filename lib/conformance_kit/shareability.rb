# frozen_string_literal: true

module ConformanceKit
  # Finds WHY a value is not Ractor-shareable: the first offending object on a
  # depth-first walk (followed as deep as it goes), the path to it, and the fix.
  # Works on any value, BasicObject included: it only calls core methods.
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
        return intrinsic_below(value, path, seen, depth) || blame(value, path) unless frozen?(value)

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
        pairs = core(:instance_variables, value).map { |ivar| [".#{ivar}", core(:instance_variable_get, value, ivar)] }
        case value
        when ::Hash then pairs + hash_children(value)
        when ::Array then pairs + value.each_with_index.map { |v, i| ["[#{i}]", v] }
        when ::Struct, ::Data then pairs + value.to_h.map { |k, v| [".#{k}", v] }
        when ::Range then pairs + [[".begin", value.begin], [".end", value.end]]
        else pairs
        end
      end

      def hash_children(hash)
        pairs = hash.flat_map { |k, v| [["{key #{label(k)}}", k], ["[#{label(k)}]", v]] }
        return pairs + [[".default_proc", hash.default_proc]] if hash.default_proc

        hash.default.nil? ? pairs : pairs + [[".default", hash.default]]
      end

      def blame(value, path)
        Culprit.new(path: path, object_class: class_name(value), reason: reason(value))
      end

      def reason(value)
        name = class_name(value)
        if callable?(value)
          "#{article(name)} #{name} that is never shareable: use Ractor.shareable_proc (Ruby 4.0) " \
            "or Ractor.make_shareable on a capture-free proc"
        elsif lock?(value) || concurrent?(value)
          "#{article(name)} #{name} that is main-only: keep per-Ractor state in ConformanceKit::Store, " \
            "or allowlist it main_only"
        elsif !frozen?(value)
          "#{article(name)} #{name} that is not frozen: freeze it at boot (Ractor.make_shareable)"
        else
          "#{article(name)} #{name} that is frozen but not shareable (an extension object, or unshareable internals)"
        end
      end

      def article(name) = name.match?(/\A[AEIOU]/) ? "an" : "a"

      # Module#=== rather than value.is_a?, which a BasicObject lacks.
      def callable?(value)
        [::Proc, ::Method, ::UnboundMethod].any? { _1 === value } # rubocop:disable Style/CaseEquality
      end

      def frozen?(value) = core(:frozen?, value)
      def core(method, value, *) = ::Kernel.instance_method(method).bind_call(value, *)

      # A key's #inspect is consumer code: never let it abort the walk.
      def label(key)
        key.inspect
      rescue StandardError
        "#<#{class_name(key)}>"
      end

      def lock?(value) = LOCKS.include?(class_name(value))
      def concurrent?(value) = class_name(value).start_with?("Concurrent::")
      def class_name(value) = ::Kernel.instance_method(:class).bind_call(value).name || "anonymous class"
    end
  end
end

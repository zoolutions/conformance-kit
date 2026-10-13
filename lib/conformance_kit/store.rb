# frozen_string_literal: true

module ConformanceKit
  # Per-Ractor lazy storage: `Store.fetch(:my_gem_cache) { {} }`.
  #
  # On Ruby 3.4+ this is `Ractor.store_if_absent`, atomic and per-Ractor. Below
  # 3.4 (and on engines without Ractor) it falls back to one Hash guarded by a
  # Mutex: safe there, because a non-main Ractor cannot run consumer code before
  # 4.0 anyway. The fallback state is created at load, never lazily, so there is
  # no check-then-set race; it is the kit's one allowlisted main-only state
  # (.conformance.yml).
  module Store
    # rubocop:disable ThreadSafety/MutableClassInstanceVariable -- main-only fallback, guarded by @fallback_lock
    @fallback_lock = Mutex.new
    @fallback_values = {}
    # rubocop:enable ThreadSafety/MutableClassInstanceVariable

    class << self
      def fetch(key, &init)
        raise ArgumentError, "ConformanceKit::Store.fetch(#{key.inspect}) needs an initializer block" unless init
        return ::Ractor.store_if_absent(key, &init) if native?

        @fallback_lock.synchronize do
          @fallback_values.fetch(key) { @fallback_values[key] = init.call }
        end
      end

      def native?
        defined?(::Ractor) ? ::Ractor.respond_to?(:store_if_absent) : false
      end
    end
  end
end

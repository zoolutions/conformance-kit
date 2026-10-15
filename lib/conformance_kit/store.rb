# frozen_string_literal: true

module ConformanceKit
  # Per-Ractor lazy storage: `Store.fetch(:my_gem_cache) { {} }`.
  #
  # On Ruby 3.4+ this is `Ractor.store_if_absent`, atomic and per-Ractor. Below
  # 3.4 (and on engines without Ractor) the main Ractor uses one Hash guarded by
  # a Mutex, created at load (never lazily, so there is no check-then-set race);
  # it is the kit's one allowlisted main-only state (.conformance.yml). A
  # non-main Ractor on 3.2/3.3 cannot read it, so it keeps its own values in
  # Ractor-local storage instead. No lock can be shared there, so threads of
  # one Ractor may each build a value, but all get the first one published.
  module Store
    # rubocop:disable ThreadSafety/MutableClassInstanceVariable -- main-only fallback, guarded by @fallback_lock
    @fallback_lock = Mutex.new
    @fallback_values = {}
    # rubocop:enable ThreadSafety/MutableClassInstanceVariable

    class << self
      def fetch(key, &init)
        raise ArgumentError, "ConformanceKit::Store.fetch(#{key.inspect}) needs an initializer block" unless init
        return ::Ractor.store_if_absent(key, &init) if native?
        return ractor_local(key, &init) unless main_ractor?

        @fallback_lock.synchronize do
          @fallback_values.fetch(key) { @fallback_values[key] = init.call }
        end
      end

      private

      def main_ractor? = !defined?(::Ractor) || ::Ractor.current == ::Ractor.main

      # Boxed, so a nil or false value is cached rather than rebuilt on every
      # fetch. Built before the check-and-publish, never between them: threads
      # that raced on the build all return whichever value was stored first.
      def ractor_local(key)
        slot = :"conformance_kit_store/#{key}"
        stored = ::Ractor.current[slot]
        return stored.first if stored

        built = [yield]
        (::Ractor.current[slot] ||= built).first
      end

      public

      def native?
        defined?(::Ractor) ? ::Ractor.respond_to?(:store_if_absent) : false
      end
    end
  end
end

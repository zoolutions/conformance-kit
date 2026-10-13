# frozen_string_literal: true

# Trips the ThreadSafety cops config/rubocop.yml turns on.
module Violating
  class << self
    attr_accessor :setting

    def cache
      @cache ||= {}
    end

    def lock
      @lock ||= Mutex.new
    end

    def worker
      Thread.new { :work }
    end
  end
end

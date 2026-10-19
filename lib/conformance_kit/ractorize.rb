# frozen_string_literal: true

module ConformanceKit
  # The ractorize job: boot a gem's test app the way Rails 8.2 runs it across
  # Ractors (`Rails.application.ractorize!`), serve requests inside non-main
  # Ractors and audit what they read. See README "The ractorize job".
  module Ractorize
    # Ractor#value is Ruby 4.0's; before it, results came back through #take.
    def self.available? = defined?(::Ractor) && ::Ractor.method_defined?(:value)
  end
end

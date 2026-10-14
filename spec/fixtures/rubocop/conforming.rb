# frozen_string_literal: true

# Passes config/rubocop.yml: per-Ractor state through the Store.
module Conforming
  def self.cache = ConformanceKit::Store.fetch(:conforming_cache) { {} }
end

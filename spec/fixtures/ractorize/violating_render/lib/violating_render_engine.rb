# frozen_string_literal: true

module ViolatingRenderEngine
  class Engine < ::Rails::Engine
  end

  class Widget
    # The violation: frozen one level deep, so the Array inside stays mutable
    # and only the main Ractor can read @registry.
    @registry = { names: %w[alpha beta] }.freeze

    class << self
      attr_reader :registry
    end
  end
end

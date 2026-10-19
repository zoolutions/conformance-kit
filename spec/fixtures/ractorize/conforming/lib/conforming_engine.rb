# frozen_string_literal: true

module ConformingEngine
  class Engine < ::Rails::Engine
  end

  # Class state set once at load and deeply frozen, so any Ractor can read it.
  class Widget
    @registry = Ractor.make_shareable({ names: %w[alpha beta] })

    class << self
      attr_reader :registry
    end
  end
end

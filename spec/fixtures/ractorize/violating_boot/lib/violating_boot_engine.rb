# frozen_string_literal: true

module ViolatingBootEngine
  class Engine < ::Rails::Engine
    # The violation: a route block appended from an initializer keeps the
    # engine as its self, so Rails can't make the route set shareable at boot.
    initializer "violating_boot_engine.routes" do |app|
      app.routes.append do
        get "/appended" => "widgets#show"
      end
    end
  end
end

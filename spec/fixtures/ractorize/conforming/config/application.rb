# frozen_string_literal: true

require "rails"
require "action_controller/railtie"
require_relative "../../production_settings"
require_relative "../lib/conforming_engine"

module ConformingApp
  class Application < Rails::Application
    RactorizeFixture.configure(config, File.expand_path("..", __dir__))
  end
end

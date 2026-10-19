# frozen_string_literal: true

class WidgetsController < ActionController::Base
  def show
    render plain: ConformingEngine::Widget.registry.fetch(:names).join(",")
  end
end

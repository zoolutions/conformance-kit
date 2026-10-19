# frozen_string_literal: true

class WidgetsController < ActionController::Base
  def show
    render plain: "unreachable: the app does not boot"
  end
end

# frozen_string_literal: true

# Runs the block as on an engine without Ractor (TruffleRuby, JRuby), then puts
# Ractor back BEFORE the example's expectations run: on Ruby 4.0 `require`
# goes through Ractor, and RSpec lazily requires its matchers. hide_const would
# keep Ractor hidden for the whole example and fail depending on spec order.
module WithoutRactor
  def without_ractor
    ractor = Object.send(:remove_const, :Ractor)
    yield
  ensure
    Object.const_set(:Ractor, ractor)
  end
end

RSpec.configure { _1.include WithoutRactor }

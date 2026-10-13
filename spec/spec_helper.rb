# frozen_string_literal: true

require "conformance_kit"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { _1.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
end

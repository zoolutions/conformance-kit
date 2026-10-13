# frozen_string_literal: true

require "securerandom"
require "conformance_kit"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { require _1 }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { _1.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
end

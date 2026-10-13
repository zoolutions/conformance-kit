# frozen_string_literal: true

# The conformance-audit fixture: three findings, one allowlisted main-only
# entry, and shareable state that must NOT be reported.
module AuditFixture
  LOCK = Mutex.new
  NAMES = %w[alpha beta] # rubocop:disable Style/MutableConstant -- the unfrozen Array finding
  FROZEN_NAMES = %w[alpha beta].freeze
  SETTINGS = Ractor.make_shareable({ retries: 3, hosts: ["a.example"] })

  module Hooks
    @on_save = proc { :saved }
    @version = 1
  end

  class Registry
    @lock = Mutex.new
  end
end

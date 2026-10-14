# frozen_string_literal: true

require_relative "conformance_kit/version"
require_relative "conformance_kit/result"
require_relative "conformance_kit/store"
require_relative "conformance_kit/shareability"
require_relative "conformance_kit/checks/consistency"
require_relative "conformance_kit/checks/thread_contention"
require_relative "conformance_kit/checks/fiber_reactor"
require_relative "conformance_kit/checks/boot_finalized"
require_relative "conformance_kit/checks/ractor_canary"

# Concurrency conformance for the zoolutions gems. See README.md for the tiers.
module ConformanceKit
end

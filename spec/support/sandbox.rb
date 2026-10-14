# frozen_string_literal: true

require "rspec/core/sandbox"

# Runs an example group in a throwaway RSpec world, so a conformance example
# can be seen FAILING without failing this suite.
module SandboxHelper
  def run_sandboxed(&definition)
    RSpec::Core::Sandbox.sandboxed do
      ConformanceKit::RSpec.register!
      group = RSpec.describe("sandboxed", &definition)
      group.run
      group.descendants.flat_map(&:examples).to_h { |example| [example.description, example] }
    end
  end
end

RSpec.configure { _1.include SandboxHelper }

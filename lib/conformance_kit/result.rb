# frozen_string_literal: true

module ConformanceKit
  # What a check returns; the RSpec and Minitest front ends turn it into a
  # pass, a failure or a skip.
  Result = Data.define(:status, :message) do
    def self.pass(message = "ok") = new(status: :passed, message: message)
    def self.fail(message) = new(status: :failed, message: message)
    def self.skip(message) = new(status: :skipped, message: message)

    def passed? = status == :passed
    def failed? = status == :failed
    def skipped? = status == :skipped
  end
end

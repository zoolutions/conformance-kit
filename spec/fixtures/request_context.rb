# frozen_string_literal: true

module Fixtures
  # VIOLATING under fibers: request state in a THREAD variable is shared by
  # every fiber of the thread, so a fiber that yields mid-request reads back
  # another fiber's value.
  module ThreadScopedContext
    def self.with(id)
      Thread.current.thread_variable_set(:fixtures_request_id, id)
      Fiber.scheduler&.yield
      seen = Thread.current.thread_variable_get(:fixtures_request_id)
      raise "request state leaked across fibers" unless seen.equal?(id)

      seen
    end
  end

  # CONFORMING: `Thread.current[]` is fiber-local in every Ruby.
  module FiberLocalContext
    def self.with(id)
      Thread.current[:fixtures_request_id] = id
      Fiber.scheduler&.yield
      seen = Thread.current[:fixtures_request_id]
      raise "request state leaked across fibers" unless seen.equal?(id)

      seen
    end
  end
end

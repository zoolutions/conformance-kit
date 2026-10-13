# frozen_string_literal: true

module Fixtures
  # VIOLATING: finalize! freezes the Hash but not the Array inside it.
  module LeakyConfig
    def self.finalize!
      @colors = { primary: %w[red blue] }.freeze
      @name = "leaky"
    end

    def self.colors = @colors
    def self.name_value = @name
  end

  # CONFORMING: finalize! deep-freezes.
  module FinalizedConfig
    def self.finalize!
      @colors = Ractor.make_shareable({ primary: %w[red blue] })
      @name = "finalized"
    end

    def self.colors = @colors
    def self.name_value = @name
  end

  # Pure operations for the non-main Ractor canary.
  module PureMath
    def self.square(number) = number * number
  end

  # VIOLATING in a Ractor: reads a constant that holds an unshareable value.
  module ConstantReader
    TABLE = { one: 1 } # rubocop:disable Style/MutableConstant -- deliberately unshareable

    def self.lookup(key) = TABLE.fetch(key)
  end
end

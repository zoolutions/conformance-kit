# frozen_string_literal: true

# Required only by name, from the load path, in audit_spec: spec/support/fixtures.rb
# never loads it, so auditing LoadPathFixture proves the name was resolved and loaded.
module LoadPathFixture
  NAMES = %w[alpha beta] # rubocop:disable Style/MutableConstant -- the one finding
end

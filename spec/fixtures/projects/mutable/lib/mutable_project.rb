# frozen_string_literal: true

# VIOLATING: an unfrozen Array in a constant.
module MutableProject
  NAMES = %w[alpha beta] # rubocop:disable Style/MutableConstant -- the finding
end

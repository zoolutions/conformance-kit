# frozen_string_literal: true

# The ancestor: rule fixture: a framework base class that keeps state on each
# subclass (as ActiveRecord::Base or Rails::Engine do), a module extended like
# ActiveSupport::Concern, and a gem namespace using both. Loaded once: a
# re-created module keeps its name in ObjectSpace and would be audited twice.
class AuditFrameworkBase
  def self.inherited(subclass)
    super
    subclass.instance_variable_set(:@columns, [])
  end
end

module AuditFrameworkConcern
  def self.extended(mod)
    super
    mod.instance_variable_set(:@deps, [])
  end
end

module AuditAncestorFixture
  TABLE = [] # rubocop:disable Style/MutableConstant -- the gem's own constant an ancestor rule must not cover

  class Model < AuditFrameworkBase
    @own_cache = {}
  end

  module Concern
    extend AuditFrameworkConcern
  end
end

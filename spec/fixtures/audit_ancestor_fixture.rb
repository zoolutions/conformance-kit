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

# A framework constant that is declared but never loaded: a rule naming it is
# stale, and the audit must not load it to find out.
module AuditAutoloadFramework
  autoload :Base, "/nonexistent/audit_autoload_framework_base"
end

module AuditAncestorFixture
  class Model < AuditFrameworkBase
    TABLE = [] # rubocop:disable Style/MutableConstant -- the gem's own constant on a covered class
    @own_cache = {}
  end

  module Concern
    extend AuditFrameworkConcern
  end
end

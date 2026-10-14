# frozen_string_literal: true

# VIOLATING under strict_autoloads: Lazy is declared but never loaded, so the
# audit cannot see it.
module AutoloadProject
  autoload :Lazy, File.expand_path("autoload_project/lazy", __dir__)
end

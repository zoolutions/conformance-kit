# frozen_string_literal: true

# What every ractorize fixture app sets: the production settings Rails' own
# railties/test/application/ractors_test.rb uses, and no reloading.
module RactorizeFixture
  def self.configure(config, root)
    config.load_defaults 8.1
    config.root = root
    config.eager_load = true
    config.enable_reloading = false
    config.logger = ActiveSupport::Ractors::Logger.new
    config.cache_store = :null_store
    config.public_file_server.enabled = false
  end
end

# frozen_string_literal: true

require_relative "lib/saltbox/sort_by_columns/version"

Gem::Specification.new do |spec|
  spec.name = "sort_by_columns"
  spec.version = Saltbox::SortByColumns::VERSION
  spec.authors = ["Sevenview Studios Inc."]
  spec.email = ["dev@sevenview.ca"]

  spec.summary = "Saltbox column-based sorting for Rails models with association support"
  spec.description = "Provides column-based sorting capabilities for Rails models with support for associations and custom scopes. Part of the Saltbox gem suite extracted from internal applications."
  spec.homepage = "https://github.com/myunio/sort_by_columns"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/myunio/sort_by_columns"
  spec.metadata["changelog_uri"] = "https://github.com/myunio/sort_by_columns/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,spec}/**/*", "*.{md,txt,gemspec}", "Rakefile", "Gemfile", ".rspec"].select { |f| File.file?(f) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_runtime_dependency "rails", ">= 7.1"
  spec.add_runtime_dependency "has_scope"

  # Development dependencies
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "sqlite3"
  spec.add_development_dependency "standardrb"
  spec.add_development_dependency "rake"
end

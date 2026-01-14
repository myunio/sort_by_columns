# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in sort_by_columns.gemspec
gemspec

# Add any additional development dependencies here that aren't part of the gem
# (currently none needed)

# Added for integration testing with a real Rails environment (Rails 8)
group :development, :test do
  gem "rails", "~> 8.0"   # Rails 8 (current as of July 2025)
  gem "sqlite3", "~> 2.1"
  gem "combustion", "~> 1.5"
  gem "has_scope", "~> 0.8.0"  # For controller integration testing
  gem "simplecov", "~> 0.22.0", require: false  # Code coverage reporting
  gem "benchmark-ips", "~> 2.12"  # Performance benchmarking
  gem "memory_profiler", "~> 1.0"  # Memory leak detection
end

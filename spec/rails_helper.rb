require "bundler/setup"
require "combustion"

# Boot Combustion with only the components we need
Combustion.path = "spec/rails_app"
Combustion.initialize! :active_record do
  # Keep the log output clean
  config.active_record.logger = nil

  # Use an in-memory SQLite DB (Rails < 6 compatibility)
  if config.active_record.sqlite3.respond_to?(:represent_boolean_as_integer=)
    config.active_record.sqlite3.represent_boolean_as_integer = true
  end
end

require "rspec/rails"
require "sort_by_columns"

# ----------------------------------------------------------------------------
# ActiveRecord schema for the dummy app
# ----------------------------------------------------------------------------
ActiveRecord::Schema.define(version: 1) do
  create_table :organizations, force: true do |t|
    t.string :name
    t.timestamps
  end

  create_table :users, force: true do |t|
    t.string :name
    t.string :email
    t.references :organization, foreign_key: true
    t.timestamps
  end
end

# ----------------------------------------------------------------------------
# Dummy models for integration tests
# ----------------------------------------------------------------------------
class Organization < ActiveRecord::Base
  has_many :users
end

class User < ActiveRecord::Base
  include Saltbox::SortByColumns::Model

  belongs_to :organization

  # Basic sortable columns for integration scenarios
  sort_by_columns :name, :email, :organization__name

  # Example custom scope to demonstrate c_ behaviour
  scope :sorted_by_full_name, ->(direction = "asc") {
    order("users.name #{direction}")
  }
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end

# Saltbox::SortByColumns

A Ruby gem that provides column-based sorting capabilities for Rails models with support for associations and custom scopes.

## Features

- **Column Sorting**: Simple column sorting with direction support
- **Association Sorting**: Sort by columns in associated models using `association__column` syntax
- **Custom Scopes**: Support for custom sorting logic via `c_*` pattern (backed by `sorted_by_*` scopes)
- **Error Handling**: Development vs production error handling strategies
- **SQL Generation**: Proper JOIN handling with NULL value management
- **Rails Integration**: Automatic Rails integration via Railtie
- **Comprehensive Testing**: Shared examples for consistent testing across models

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sort_by_columns', git: 'https://github.com/myunio/sort_by_columns.git'
```

And then execute:

```bash
bundle install
```

## Usage

### Model Setup

In your model, include the `Saltbox::SortByColumns::Model` module and specify which columns can be sorted:

```ruby
class User < ApplicationRecord
  include Saltbox::SortByColumns::Model

  belongs_to :organization
  has_many :posts

  sort_by_columns :name, :email, :created_at, :organization__name
end
```

### Controller Setup

In your controller, include the `Saltbox::SortByColumns::Controller` module:

```ruby
class UsersController < ApplicationController
  include Saltbox::SortByColumns::Controller

  def index
    @users = apply_scopes(User).page(params[:page])
  end
end
```

> **Note**: Make sure you call `apply_scopes` on your model scope in the controller action, or the sorting parameters won't be processed.

### API Usage

With everything set up, you can now pass the `sort` parameter in your API requests:

```
GET /users?sort=name
GET /users?sort=name:asc
GET /users?sort=name:desc
GET /users?sort=name:asc,created_at:desc
GET /users?sort=organization__name:asc
```

## Integration with has_scope

This gem is built on top of the [has_scope](https://github.com/heartcombo/has_scope) gem, which provides the foundation for parameter-based scope application in Rails controllers.

### How it works

**has_scope** handles the parameter processing and scope application, while **sort_by_columns** provides the sorting logic:

1. **Parameter Processing**: has_scope automatically reads the `sort` parameter from the request
2. **Scope Definition**: This gem automatically defines a `sorted_by_columns` scope on your models
3. **Scope Application**: has_scope's `apply_scopes` method applies the sorting scope with the parameter value
4. **Sorting Logic**: This gem processes the sort parameter and generates the appropriate SQL

### The `apply_scopes` method

The `apply_scopes` method in your controllers comes from has_scope, not from this gem:

```ruby
class UsersController < ApplicationController
  include Saltbox::SortByColumns::Controller  # This adds has_scope functionality

  def index
    # apply_scopes comes from has_scope
    # It automatically applies the sorted_by_columns scope when sort param is present
    @users = apply_scopes(User).page(params[:page])
  end
end
```

### Behind the scenes

When you include `Saltbox::SortByColumns::Controller`, it automatically sets up has_scope for the `sort` parameter:

```ruby
# This is done automatically when you include the controller module
has_scope :sorted_by_columns, using: :sort, type: :hash
```

This means:
- has_scope looks for a `sort` parameter in the request
- If found, it calls the `sorted_by_columns` scope on your model with the parameter value
- This gem provides the `sorted_by_columns` scope implementation on your models

### Parameter flow

Here's how a request like `GET /users?sort=name:desc,organization__name:asc` gets processed:

1. **has_scope** extracts `sort=name:desc,organization__name:asc` from params
2. **has_scope** calls `User.sorted_by_columns("name:desc,organization__name:asc")`
3. **This gem** parses the sort string and generates appropriate SQL with JOINs and ORDER clauses
4. **has_scope** applies the resulting scope to build the final query

### Why has_scope?

has_scope provides several benefits that this gem leverages:

- **Automatic parameter binding**: No need to manually check for sort parameters
- **Scope chaining**: Works seamlessly with other scopes and query methods
- **Consistent API**: Follows Rails conventions for parameter-based filtering
- **Flexibility**: Easy to combine with other has_scope filters like search, pagination, etc.

For more information about has_scope itself, see the [official documentation](https://github.com/heartcombo/has_scope).

## Column Types

### Simple Columns

For simple model columns, just pass the column name:

```ruby
sort_by_columns :name, :email, :created_at
```

API usage:
```
GET /users?sort=name:asc
GET /users?sort=email:desc,created_at:asc
```

### Association Columns

For columns on associated models, use the `association__column` format:

```ruby
class User < ApplicationRecord
  belongs_to :organization
  
  include Saltbox::SortByColumns::Model
  sort_by_columns :name, :organization__name, :organization__created_at
end
```

API usage:
```
GET /users?sort=organization__name:asc
GET /users?sort=name:asc,organization__name:desc
```

#### Association Column Features

- Uses `LEFT OUTER JOIN` to ensure records with null associations are included
- Handles null values gracefully using `NULLS LAST` (for ascending sorts) or `NULLS FIRST` (for descending sorts)
- Supports custom `class_name` associations by properly using the association name as the table alias

### Custom Scope Columns

For complex sorting logic, use custom scopes with the `c_` prefix. **The naming convention is critical**: a sortable column named `c_*` must be backed by a scope named `sorted_by_*`.

```ruby
class User < ApplicationRecord
  include Saltbox::SortByColumns::Model
  
  has_many :addresses
  
  # The sortable column name: c_full_address
  sort_by_columns :name, :c_full_address

  # Required scope name: sorted_by_full_address (c_ becomes sorted_by_)
  scope :sorted_by_full_address, ->(direction) {
    joins(:addresses)
      .order("addresses.street #{direction}, addresses.city #{direction}")
  }
end
```

#### Naming Convention Examples:

- `c_full_address` → `sorted_by_full_address`
- `c_total_orders` → `sorted_by_total_orders`
- `c_latest_activity` → `sorted_by_latest_activity`

API usage:
```
GET /users?sort=c_full_address:desc
```

> **Important**: Custom sort columns must be used alone and cannot be combined with other columns. For example, `c_full_address,name` will not work.

## Error Handling

The gem handles invalid columns differently based on the environment:

### Development Environment
- Raises `ArgumentError` for invalid columns to help catch issues during development
- Provides detailed error messages with suggested fixes

### Production Environment
- Silently ignores invalid columns and logs warnings
- Continues processing valid columns when possible
- For custom scopes, ignores the entire sort operation if invalid

## Rails Integration

The gem includes a Railtie that automatically integrates with Rails applications:

- **Automatic Loading**: The gem automatically loads when Rails starts
- **Shared Examples**: RSpec shared examples are automatically loaded when RSpec is available
- **Configuration**: Provides `Rails.application.config.saltbox_sort_by_columns` for future configuration options

The Railtie handles all the integration automatically - you don't need to do anything special.

## Testing

### Using Shared Examples in Your App

The gem includes shared examples to help you test your sortable models:

```ruby
# spec/models/user_spec.rb
require 'rails_helper'

RSpec.describe User, type: :model do
  it_behaves_like "sortable by columns", {
    allowed_columns: [:name, :email, :created_at],
    disallowed_column: :password,
    associated_column: {
      name: :organization__name,
      expected_sql: "organizations.name"
    }
  }
end
```

The shared examples are automatically loaded when RSpec is available, so you don't need to require them manually.

### Running Tests

```bash
# Run all tests with coverage
bundle exec rspec

# Run specific test phases
bundle exec rspec spec/saltbox/sort_by_columns/model_basic_spec.rb       # Core functionality
bundle exec rspec spec/saltbox/sort_by_columns/model_edge_cases_spec.rb  # Edge cases & validation
bundle exec rspec spec/integration/                                      # Integration tests

# Run with specific output format
bundle exec rspec --format documentation
```

### Comprehensive Documentation

For complete testing information, see:

- **[TESTING.md](TESTING.md)** - Comprehensive testing guide including patterns, conventions, and advanced test running options
- **[EXAMPLES.md](EXAMPLES.md)** - Real-world usage examples for e-commerce, user management, project management, and more

### Test Quality Features

- **Environment-Aware Testing**: Different behaviors in development vs production
- **Security Testing**: Parameter pollution and SQL injection prevention
- **Performance Testing**: Memory efficiency and concurrent request handling  
- **Real Rails Integration**: Uses Combustion framework for authentic Rails testing
- **Comprehensive Edge Cases**: Unicode handling, malformed inputs, logger failures
- **Mock and Integration**: Both isolated unit tests and full-stack integration tests

## Dependencies

- Rails >= 7.0
- has_scope ~> 0.8

## Local Development

For local development of the gem itself:

```bash
# Set up local development
bundle config local.sort_by_columns /path/to/sort_by_columns
bundle install

# Run tests
rake spec

# Run linter
rake standard

# Build the gem
rake build
```

## Version Management

The gem includes rake tasks for managing version bumps:

```bash
# Check current version
rake version:current

# Preview what the next version would be (no changes made)
rake 'version:preview[patch]'   # Preview patch bump (1.0.1 → 1.0.2)
rake 'version:preview[minor]'   # Preview minor bump (1.0.1 → 1.1.0)
rake 'version:preview[major]'   # Preview major bump (1.0.1 → 2.0.0)

# Bump version (updates version.rb, CHANGELOG.md, commits, and tags)
rake 'version:bump[patch]'      # Bump patch version
rake 'version:bump[minor]'      # Bump minor version
rake 'version:bump[major]'      # Bump major version
```

**Note:** The square brackets must be quoted in zsh/bash to prevent shell expansion. Use single quotes around the entire task name.

After bumping, the task will:
- Update `lib/saltbox/sort_by_columns/version.rb`
- Add a new entry template to `CHANGELOG.md`
- Create a git commit
- Create an annotated git tag (e.g., `v1.0.2`)
- Show you the commands to push to GitHub

**Example release workflow:**
```bash
# 1. Preview the version bump
rake 'version:preview[patch]'

# 2. Bump the version
rake 'version:bump[patch]'

# 3. Edit CHANGELOG.md to fill in the changes

# 4. Push to GitHub
git push origin main --follow-tags
```

For development in a Rails application using the gem:

```bash
# Set up local development when needed
bundle config local.sort_by_columns /path/to/sort_by_columns
bundle install

# Return to remote gem when done
bundle config --delete local.sort_by_columns
bundle install
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run the tests (`rake spec`)
5. Run the linter (`rake standard`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## License

This gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Examples

### Quick Start Examples

#### Basic Model with Simple Columns

```ruby
class Post < ApplicationRecord
  include Saltbox::SortByColumns::Model

  sort_by_columns :title, :published_at, :view_count
end
```

#### Model with Association Columns

```ruby
class Member < ApplicationRecord
  include Saltbox::SortByColumns::Model

  belongs_to :organization
  belongs_to :current_status, class_name: "Status", optional: true

  sort_by_columns :name, :email, :organization__name, :current_status__name
end
```

#### Model with Custom Scope

```ruby
class User < ApplicationRecord
  include Saltbox::SortByColumns::Model

  has_many :orders

  # Custom sortable column: c_total_orders
  sort_by_columns :name, :email, :c_total_orders

  # Required scope: sorted_by_total_orders (c_ becomes sorted_by_)
  scope :sorted_by_total_orders, ->(direction) {
    joins(:orders)
      .group('users.id')
      .order("COUNT(orders.id) #{direction}")
  }
end
```

#### Controller Implementation

```ruby
class UsersController < ApplicationController
  include Saltbox::SortByColumns::Controller

  def index
    @users = apply_scopes(User.includes(:organization))
                .page(params[:page])
                .per(params[:per_page] || 25)
  end
end
```

#### API Usage

```bash
# Sort by name ascending (default)
curl "http://localhost:3000/users?sort=name"

# Sort by name descending
curl "http://localhost:3000/users?sort=name:desc"

# Multiple column sort
curl "http://localhost:3000/users?sort=name:asc,created_at:desc"

# Association column sort
curl "http://localhost:3000/users?sort=organization__name:asc"

# Custom scope sort
curl "http://localhost:3000/users?sort=c_total_orders:desc"
```

### Real-World Implementation Examples

For comprehensive, production-ready examples including:

- **E-commerce Product Catalog** with popularity and rating sorting
- **User Management System** with activity scores and organization filtering  
- **Project Management Dashboard** with completion rates and overdue tasks
- **Blog Platform** with engagement metrics and content management
- **Customer Support System** with ticket prioritization and response times
- **API Integration Patterns** for REST and GraphQL APIs
- **Frontend Integration** with React, Vue.js, and URL state management

See **[EXAMPLES.md](EXAMPLES.md)** for complete implementation guides with models, controllers, views, and testing patterns. 

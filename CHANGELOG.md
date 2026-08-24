# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.1] - 2026-08-24

### Fixed
- Alias every associated table in compound sort expressions.

## [2.0.0] - 2026-01-14

### Added
- 

### Changed
- 

### Fixed
- 

### Deprecated
- 

### Removed
- 

### Security
- 


## [1.0.1] - 2025-07-20

### Fixed
- Fixed `NoMethodError: undefined method 'instance' for class ActiveSupport::Deprecation` in Rails 8+
- Updated deprecation warnings to use modern Rails 7.1+ `Rails.application.deprecators` API
- Simplified deprecation code since gem now requires Rails 7.1+ minimum

## [1.0.0] - 2025-07-20

### Added
- New primary method `sort_by_columns` for defining sortable columns, aligning with the gem name

### Changed
- **BREAKING (with deprecation)**: `column_sortable_by` is now deprecated in favor of `sort_by_columns`
  - The old method still works but shows deprecation warnings
  - All documentation and examples updated to use `sort_by_columns`
  - Error messages updated to reference the new method name

### Deprecated
- `column_sortable_by` method - use `sort_by_columns` instead
  - Will be removed in a future major version
  - Shows ActiveSupport::Deprecation warnings when used

## Migration Guide

### From `column_sortable_by` to `sort_by_columns`

Simply replace all instances of `column_sortable_by` with `sort_by_columns`:

```ruby
# Old (deprecated)
class User < ApplicationRecord
  include SortByColumns::Model
  column_sortable_by :name, :email, :created_at, :organization__name
end

# New (recommended)
class User < ApplicationRecord
  include SortByColumns::Model
  sort_by_columns :name, :email, :created_at, :organization__name
end
```

The functionality is identical - only the method name has changed to better align with the gem's name "sort by columns". 

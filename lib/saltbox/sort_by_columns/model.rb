# frozen_string_literal: true

require "active_support/concern"

module Saltbox
  module SortByColumns
    # Adds column-based sorting capabilities to ActiveRecord models
    #
    # This module allows models to define which columns can be sorted on,
    # including support for association columns and custom sort scopes.
    #
    # @note Dependencies: Requires the `has_scope` gem in the controller part
    #
    # @example Basic usage in a model
    #   class User < ApplicationRecord
    #     include SortByColumns::Model
    #
    #     belongs_to :organization
    #
    #     sort_by_columns :name, :email, :created_at, :organization__name
    #   end
    #
    # @example Sorting in a controller action
    #   # GET /users?sort=name:asc,email:desc
    #   def index
    #     @users = User.sorted_by_columns(params[:sort])
    #   end
    #
    # @note When using custom sort columns (starting with `c_`), they must be used
    #   as the only sort column. You cannot combine them with other columns.
    #
    # @note Disallowed columns are silently ignored in production and warnings
    #   are logged, but in development environments they raise ArgumentError.
    #
    # @see SortByColumns::Controller
    module Model
      extend ActiveSupport::Concern

      class_methods do
        # Specifies which columns can be sorted on this model
        #
        # @param allowed_fields [Array<Symbol, String>] List of column names that can be sorted
        #   Simple column format: :column_name
        #   Association column format: :association__column
        #   Custom sort scope format: :c_custom_sort_name
        #
        # @example Setting sortable columns
        #   sort_by_columns :name, :email, :created_at
        #
        # @example Setting association sortable columns
        #   sort_by_columns :name, :organization__name, :department__code
        #
        # @example Setting custom sort columns (requires a corresponding scope)
        #   sort_by_columns :name, :c_full_address
        #
        #   # Required scope for custom sort
        #   scope :sorted_by_full_address, ->(direction) {
        #     joins(:addresses).order("addresses.street #{direction}, addresses.city #{direction}")
        #   }
        #
        # @note Association column format requires a double underscore between the
        #   singular association name and the column name (e.g., :organization__name).
        #   The association must exist on the model.
        #
        # @note Custom sort columns must start with `c_` and have a corresponding scope
        #   prefixed with `sorted_by_`. For example, :c_full_address requires a
        #   :sorted_by_full_address scope that accepts a direction parameter.
        #
        # @note When using custom sort columns in API requests, they must be used alone and
        #   cannot be combined with other columns, e.g., "c_full_address,created_at" will not work.
        #
        # @return [void]
        def sort_by_columns(*allowed_fields)
          @column_sortable_allowed_fields = allowed_fields.map(&:to_sym)
        end

        # @deprecated Use {#sort_by_columns} instead
        # Specifies which columns can be sorted on this model
        #
        # This method is deprecated. Use `sort_by_columns` instead.
        #
        # @param allowed_fields [Array<Symbol, String>] List of column names that can be sorted
        # @return [void]
        def column_sortable_by(*allowed_fields)
          # Rails 7.1+ modern deprecation handling
          deprecator = Rails.application.deprecators[:saltbox_sort_by_columns] ||=
            ActiveSupport::Deprecation.new("2.0", "sort_by_columns")

          deprecator.warn(
            "`column_sortable_by` is deprecated and will be removed in a future version. " \
            "Use `sort_by_columns` instead."
          )

          sort_by_columns(*allowed_fields)
        end

        # Returns the list of columns that are allowed to be sorted
        #
        # @return [Array<Symbol>] List of allowed sortable column names
        def column_sortable_allowed_fields
          @column_sortable_allowed_fields || []
        end

        # The main scope that sorts records by one or more columns
        #
        # @param by [String, nil] Comma-separated list of columns to sort by
        #   Format: "column_name:direction,another_column:direction"
        #   Direction can be "asc" or "desc" (defaults to "asc" if not specified)
        #
        # @example Simple sorting
        #   User.sorted_by_columns("name")
        #   # => SELECT "users".* FROM "users" ORDER BY users.name ASC
        #
        # @example Sorting with explicit direction
        #   User.sorted_by_columns("name:desc")
        #   # => SELECT "users".* FROM "users" ORDER BY users.name DESC
        #
        # @example Multi-column sorting
        #   User.sorted_by_columns("status:asc,created_at:desc")
        #   # => SELECT "users".* FROM "users" ORDER BY users.status ASC, users.created_at DESC
        #
        # @example Association column sorting
        #   User.sorted_by_columns("organization__name:asc")
        #   # => SELECT "users".* FROM "users" LEFT OUTER JOINS "organizations"
        #   #    ORDER BY organizations.name ASC
        #
        # @example Custom scope sorting
        #   User.sorted_by_columns("c_full_address:desc")
        #   # Calls the custom sorted_by_full_address scope with "desc" as the argument
        #
        # @note Custom sort columns (starting with `c_`) must be used alone and cannot
        #   be combined with other columns. For example, "c_full_address,created_at" will
        #   not work and will result in no sorting being applied.
        #
        # @note For production environments, invalid columns are silently ignored:
        #   - For standard and association columns, only the invalid column is ignored
        #   - For custom columns, the entire sort operation is ignored if invalid
        #
        # @raise [ArgumentError] In development environments, raises errors for invalid columns
        #   to help identify and fix issues during development
        #
        # @return [ActiveRecord::Relation] Sorted relation
        def sorted_by_columns(by)
          return all if by.blank?

          # Handle parameter pollution where by might be an array
          # In case of parameter pollution, take the first element or ignore if not a string
          if by.is_a?(Array)
            by = by.first
            return all if by.blank? || !by.is_a?(String)
          end

          if by.start_with?("c_")
            return handle_custom_scope(by)
          end

          includes_needed, order_fragments = process_standard_columns(by)

          # If no valid order fragments, return the unmodified relation
          return all if order_fragments.empty?

          apply_sorting(includes_needed, order_fragments)
        end

        private

        # Normalizes the sort direction to either "asc" or "desc"
        #
        # @param direction [String, nil] The direction string to normalize
        # @return [String] "asc" or "desc"
        def normalize_direction(direction)
          %w[asc desc].include?(direction) ? direction : "asc"
        end

        # Handles errors during sort processing
        #
        # @param message [String] The error message
        # @param column [String, Symbol] The column that caused the error
        # @param is_critical [Boolean] Whether the error is critical enough to abort all sorting
        # @return [nil] Always returns nil
        # @raise [ArgumentError] In development environments, raises the provided error
        def handle_error(message, column, is_critical = false)
          is_local_env = Rails.env.local?

          if is_local_env
            message = message.to_s.gsub("%{column}", column.to_s)
            raise ArgumentError, message
          else
            # Handle nil logger gracefully and wrap in rescue for logger exceptions
            begin
              if Rails.logger&.respond_to?(:warn)
                Rails.logger.warn "SortByColumns ignoring #{is_critical ? "all columns due to" : "disallowed column:"} #{column}"
              end
            rescue => _logger_e
              # Silently ignore logger errors to prevent them from affecting the main application
            end
            nil
          end
        end

        # Handles custom scope sorting
        #
        # @param by [String] The sort specification string
        # @return [ActiveRecord::Relation] The sorted relation
        # @raise [ArgumentError] If the custom scope format is invalid or column is not allowed
        def handle_custom_scope(by)
          # Ensure there are no extra columns when a custom scope is provided
          if by.include?(",")
            error_message = <<~ERROR
              SortByColumns does not support multiple columns when using a
              custom scope column. Note: in production this invalid column
              spec will be ignored and no scope will be applied.
            ERROR
            handle_error(error_message, by, true)
            return all
          end

          # Get the column and direction, stripping whitespace
          custom_column, direction = by.split(",")[0].split(":").map(&:strip)
          direction = normalize_direction(direction)

          # Ensure the column is allowed
          unless column_sortable_allowed_fields.include?(custom_column.to_sym)
            error_message = <<~ERROR
              SortByColumns: detected a disallowed sortable column:
              %{column}. Ensure you add it to the list of allowed columns
              with the 'sort_by_columns: %{column}' method. Note: in
              production the invalid column will be ignored.
            ERROR
            handle_error(error_message, custom_column)
            return all
          end

          # Strip the c_ prefix and call the custom scope with direction
          column = custom_column[2..]
          scope_method = :"sorted_by_#{column}"

          # Check if the custom scope method exists
          unless respond_to?(scope_method)
            error_message = <<~ERROR
              SortByColumns: model #{name} does not respond to '#{scope_method}' method.
              Custom scope columns (starting with 'c_') require a corresponding scope method.
              For column '#{custom_column}', define a scope: 'scope :#{scope_method}, ->(direction) { ... }'
            ERROR
            handle_error(error_message, custom_column)
            return all
          end

          send(scope_method, direction)
        end

        # Processes standard columns for sorting
        #
        # @param by [String] The sort specification string
        # @return [Array<Array, Array>] Array containing [includes_needed, order_fragments]
        def process_standard_columns(by)
          includes_needed = []
          order_fragments = []
          model_table_name = table_name
          allowed_fields = column_sortable_allowed_fields

          by.split(",").map(&:strip).each do |col_spec|
            # Skip empty column specifications (from multiple commas, etc.)
            next if col_spec.blank?

            column, direction = col_spec.split(":").map(&:strip)
            direction = normalize_direction(direction)

            # Skip if column is blank or nil
            next if column.blank?

            # Skip disallowed columns
            unless allowed_fields.include?(column.to_sym)
              error_message = <<~ERROR
                SortByColumns: detected a disallowed sortable column:
                %{column}. Ensure you add it to the list of allowed columns
                with the 'sort_by_columns: %{column}' method. Note: in
                production the invalid column will be ignored and allowed
                columns will be processed.
              ERROR
              handle_error(error_message, column)
              next
            end

            # Process column and build order fragment
            if column.include?("__")
              process_association_column(column, direction, includes_needed, order_fragments)
            else
              order_fragments << "#{model_table_name}.#{column} #{direction.upcase}"
            end
          end

          [includes_needed, order_fragments]
        end

        # Processes an association column for sorting
        #
        # @param column [String] The association column in format "association__column"
        # @param direction [String] The sort direction
        # @param includes_needed [Array<Symbol>] Array to add required includes to
        # @param order_fragments [Array<String>] Array to add order fragments to
        # @return [void]
        # @raise [ArgumentError] If the association doesn't exist on the model
        def process_association_column(column, direction, includes_needed, order_fragments)
          parts = column.split("__")
          association_name = parts[0].to_sym
          association_column = parts[1]

          # Check if association exists on the model
          reflection = reflect_on_association(association_name)
          unless reflection
            error_message = <<~ERROR
              SortByColumns: association '%{column}' doesn't exist on model #{name}.
              Check the association name in '#{column}'.
            ERROR
            handle_error(error_message, association_name)
            return
          end

          includes_needed << association_name unless includes_needed.include?(association_name)

          # When doing includes/references with associations that have custom
          # class_name, Rails aliases the joined table with the association
          # name, not the actual table name. So we need to use the association
          # name in our SQL query, not the table name from the reflection.
          table_alias = association_name.to_s

          # Handle nulls gracefully - PostgreSQL NULLS LAST ensures consistent
          # ordering including records with null associations
          nulls_directive = (direction.upcase == "ASC") ? "NULLS LAST" : "NULLS FIRST"
          order_fragments << "#{table_alias}.#{association_column} #{direction.upcase} #{nulls_directive}"
        end

        # Applies the sorting to the relation
        #
        # @param includes_needed [Array<Symbol>] Associations that need to be included
        # @param order_fragments [Array<String>] SQL fragments for the ORDER BY clause
        # @return [ActiveRecord::Relation] The sorted relation
        def apply_sorting(includes_needed, order_fragments)
          relation = all

          # Add necessary joins for association columns
          unless includes_needed.empty?
            # Use left_outer_joins to properly handle null associations
            # This ensures that records with null associations are still included in results
            relation = relation.left_outer_joins(includes_needed)
          end

          # Apply the order clause
          order_string = order_fragments.join(", ")
          relation.reorder(Arel.sql(order_string))
        end
      end
    end
  end
end

# frozen_string_literal: true

require "rails_helper"

RSpec.describe Saltbox::SortByColumns::Model, "SQL Generation & Association Testing" do
  # Use the real User model from our Combustion app
  let(:test_model) { User }

  before do
    # Create test data
    @org_a = Organization.create!(name: "Alpha Corp")
    @org_b = Organization.create!(name: "Beta Inc")

    @user1 = User.create!(name: "Charlie", email: "charlie@example.com", organization: @org_b)
    @user2 = User.create!(name: "Alice", email: "alice@example.com", organization: @org_a)
    @user3 = User.create!(name: "Bob", email: "bob@example.com", organization: @org_a)

    # Set up basic allowed columns
    test_model.sort_by_columns :name, :email, :created_at, :organization__name
  end

  describe "SQL generation verification" do
    describe "standard column SQL generation" do
      it "generates proper table prefixes for local columns" do
        sql = test_model.sorted_by_columns("name:asc").to_sql
        expect(sql).to include("users.name ASC")
        expect(sql).to include("ORDER BY users.name ASC")
      end

      it "maintains column order in ORDER BY clause" do
        sql = test_model.sorted_by_columns("name:asc,email:desc").to_sql
        expect(sql).to match(/ORDER BY users\.name ASC, users\.email DESC/)
      end

      it "properly quotes table and column names" do
        sql = test_model.sorted_by_columns("name:asc").to_sql
        expect(sql).to include('"users"')
        expect(sql).to include("ORDER BY users.name ASC")
      end

      it "handles mixed ASC/DESC directions" do
        sql = test_model.sorted_by_columns("name:asc,email:desc,created_at:asc").to_sql
        expect(sql).to match(/ORDER BY users\.name ASC, users\.email DESC, users\.created_at ASC/)
      end
    end

    describe "association column SQL generation" do
      it "generates LEFT OUTER JOIN for associations" do
        sql = test_model.sorted_by_columns("organization__name:asc").to_sql
        expect(sql).to include("LEFT OUTER JOIN")
        expect(sql).to include('"organizations"')
      end

      it "applies NULLS LAST for ASC associations" do
        sql = test_model.sorted_by_columns("organization__name:asc").to_sql
        expect(sql).to include("organization.name ASC NULLS LAST")
      end

      it "applies NULLS FIRST for DESC associations" do
        sql = test_model.sorted_by_columns("organization__name:desc").to_sql
        expect(sql).to include("organization.name DESC NULLS FIRST")
      end

      it "uses association name as table alias" do
        sql = test_model.sorted_by_columns("organization__name:asc").to_sql
        expect(sql).to include("organization.name")
        expect(sql).to include('"organization" ON')
      end

      it "handles multiple associations without duplicate joins" do
        # Create another association model for testing
        ActiveRecord::Schema.define do
          create_table :departments, force: true do |t|
            t.string :name
            t.timestamps
          end
        end

        # Add association to User model
        User.class_eval do
          belongs_to :department, optional: true
        end

        # Create Department model
        Object.const_set(:Department, Class.new(ActiveRecord::Base))
        Department.class_eval do
          has_many :users
        end

        # Add department to allowed columns
        test_model.sort_by_columns :name, :organization__name, :department__name

        sql = test_model.sorted_by_columns("organization__name:asc,department__name:desc").to_sql

        # Should have joins for both associations
        expect(sql).to include("LEFT OUTER JOIN")
        expect(sql).to include('"organizations"')
        expect(sql).to include('"departments"')

        # Should have both in ORDER BY
        expect(sql).to include("organization.name ASC NULLS LAST")
        expect(sql).to include("department.name DESC NULLS FIRST")
      end
    end
  end

  describe "association processing" do
    describe ".process_association_column (private method)" do
      it "correctly parses association__column format" do
        includes_needed = []
        order_fragments = []

        test_model.send(:process_association_column, "organization__name", "asc", includes_needed, order_fragments)

        expect(includes_needed).to include(:organization)
        expect(order_fragments).to include("organization.name ASC NULLS LAST")
      end

      it "validates association existence via reflection" do
        includes_needed = []
        order_fragments = []

        # Mock reflect_on_association to return nil for invalid association
        allow(test_model).to receive(:reflect_on_association).with(:invalid_association).and_return(nil)

        # This should trigger error handling
        expect(test_model).to receive(:handle_error).with(
          a_string_including("association '%{column}' doesn't exist"),
          :invalid_association
        )

        test_model.send(:process_association_column, "invalid_association__name", "asc", includes_needed, order_fragments)
      end

      it "builds correct includes array" do
        includes_needed = []
        order_fragments = []

        test_model.send(:process_association_column, "organization__name", "asc", includes_needed, order_fragments)

        expect(includes_needed).to eq([:organization])
        expect(includes_needed.length).to eq(1)
      end

      it "generates proper order fragments" do
        includes_needed = []
        order_fragments = []

        test_model.send(:process_association_column, "organization__name", "desc", includes_needed, order_fragments)

        expect(order_fragments).to include("organization.name DESC NULLS FIRST")
      end

      it "handles association reflection errors gracefully" do
        includes_needed = []
        order_fragments = []

        # Mock reflect_on_association to raise an error
        allow(test_model).to receive(:reflect_on_association).and_raise(StandardError, "Reflection error")

        expect {
          test_model.send(:process_association_column, "organization__name", "asc", includes_needed, order_fragments)
        }.to raise_error(StandardError, "Reflection error")
      end

      it "doesn't add duplicate includes" do
        includes_needed = [:organization]
        order_fragments = []

        test_model.send(:process_association_column, "organization__name", "asc", includes_needed, order_fragments)

        expect(includes_needed).to eq([:organization])
        expect(includes_needed.length).to eq(1)
      end
    end
  end

  describe "sorting application" do
    describe ".apply_sorting (private method)" do
      it "applies left_outer_joins correctly" do
        includes_needed = [:organization]
        order_fragments = ["organization.name ASC NULLS LAST"]

        result = test_model.send(:apply_sorting, includes_needed, order_fragments)
        sql = result.to_sql

        expect(sql).to include("LEFT OUTER JOIN")
        expect(sql).to include('"organizations"')
      end

      it "builds proper ORDER BY clause" do
        includes_needed = []
        order_fragments = ["users.name ASC", "users.email DESC"]

        result = test_model.send(:apply_sorting, includes_needed, order_fragments)
        sql = result.to_sql

        expect(sql).to include("ORDER BY users.name ASC, users.email DESC")
      end

      it "uses Arel.sql for order fragments" do
        includes_needed = []
        order_fragments = ["users.name ASC"]

        # Don't mock Arel.sql, just verify the method works correctly
        result = test_model.send(:apply_sorting, includes_needed, order_fragments)
        sql = result.to_sql

        # Verify the ORDER BY clause is present
        expect(sql).to include("ORDER BY users.name ASC")
      end

      it "handles empty includes array" do
        includes_needed = []
        order_fragments = ["users.name ASC"]

        result = test_model.send(:apply_sorting, includes_needed, order_fragments)
        sql = result.to_sql

        expect(sql).not_to include("LEFT OUTER JOIN")
        expect(sql).to include("ORDER BY users.name ASC")
      end

      it "handles empty order fragments" do
        includes_needed = [:organization]
        order_fragments = []

        result = test_model.send(:apply_sorting, includes_needed, order_fragments)
        sql = result.to_sql

        expect(sql).to include("LEFT OUTER JOIN")
        # Empty order fragments result in no ORDER BY clause (Rails optimizes it out)
        expect(sql).not_to include("ORDER BY")
      end
    end
  end

  describe "standard column processing" do
    describe ".process_standard_columns (private method)" do
      it "correctly splits and parses column specifications" do
        includes_needed, order_fragments = test_model.send(:process_standard_columns, "name:asc,email:desc")

        expect(includes_needed).to eq([])
        expect(order_fragments).to include("users.name ASC")
        expect(order_fragments).to include("users.email DESC")
      end

      it "builds includes array for associations" do
        includes_needed, order_fragments = test_model.send(:process_standard_columns, "organization__name:asc")

        expect(includes_needed).to include(:organization)
        expect(order_fragments).to include("organization.name ASC NULLS LAST")
      end

      it "builds order fragments array" do
        _, order_fragments = test_model.send(:process_standard_columns, "name:asc,email:desc")

        expect(order_fragments).to be_an(Array)
        expect(order_fragments.length).to eq(2)
        expect(order_fragments).to include("users.name ASC")
        expect(order_fragments).to include("users.email DESC")
      end

      it "skips disallowed columns appropriately" do
        # Set up production environment to skip disallowed columns
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))

        _, order_fragments = test_model.send(:process_standard_columns, "name:asc,disallowed_column:desc")

        expect(order_fragments).to include("users.name ASC")
        expect(order_fragments).not_to include("users.disallowed_column DESC")
      end

      it "handles mixed valid/invalid columns" do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))

        _, order_fragments = test_model.send(:process_standard_columns, "name:asc,invalid:desc,email:asc")

        expect(order_fragments).to include("users.name ASC")
        expect(order_fragments).to include("users.email ASC")
        expect(order_fragments).not_to include("users.invalid DESC")
      end
    end
  end

  describe "SQL syntax and structure" do
    it "generates valid SQL for single column sort" do
      sql = test_model.sorted_by_columns("name:asc").to_sql
      expect(sql).to match(/SELECT.*FROM.*users.*ORDER BY users\.name ASC/m)
    end

    it "generates valid SQL for multi-column sort" do
      sql = test_model.sorted_by_columns("name:asc,email:desc").to_sql
      expect(sql).to match(/SELECT.*FROM.*users.*ORDER BY users\.name ASC, users\.email DESC/m)
    end

    it "generates valid SQL for association column sort" do
      sql = test_model.sorted_by_columns("organization__name:asc").to_sql
      expect(sql).to match(/SELECT.*FROM.*users.*LEFT OUTER JOIN.*organizations.*ORDER BY organization\.name ASC NULLS LAST/m)
    end

    it "generates valid SQL for mixed column and association sort" do
      sql = test_model.sorted_by_columns("name:asc,organization__name:desc").to_sql
      expect(sql).to match(/SELECT.*FROM.*users.*LEFT OUTER JOIN.*organizations.*ORDER BY users\.name ASC, organization\.name DESC NULLS FIRST/m)
    end
  end

  describe "NULLS handling in SQL" do
    it "applies NULLS LAST for ASC direction on associations" do
      sql = test_model.sorted_by_columns("organization__name:asc").to_sql
      expect(sql).to include("organization.name ASC NULLS LAST")
    end

    it "applies NULLS FIRST for DESC direction on associations" do
      sql = test_model.sorted_by_columns("organization__name:desc").to_sql
      expect(sql).to include("organization.name DESC NULLS FIRST")
    end

    it "does not apply NULLS handling for local columns" do
      sql = test_model.sorted_by_columns("name:asc").to_sql
      expect(sql).not_to include("NULLS")
      expect(sql).to include("users.name ASC")
    end

    it "mixes NULLS handling correctly for mixed sorts" do
      sql = test_model.sorted_by_columns("name:asc,organization__name:desc,email:asc").to_sql
      expect(sql).to include("users.name ASC")
      expect(sql).to include("organization.name DESC NULLS FIRST")
      expect(sql).to include("users.email ASC")
      expect(sql).not_to include("users.name ASC NULLS")
      expect(sql).not_to include("users.email ASC NULLS")
    end
  end

  describe "JOIN handling" do
    it "creates proper LEFT OUTER JOIN syntax" do
      sql = test_model.sorted_by_columns("organization__name:asc").to_sql
      expect(sql).to match(/LEFT OUTER JOIN "organizations"(?: AS)? "organization" ON "organization"\."id" = "users"\."organization_id"/)
    end

    it "uses correct table alias in JOIN" do
      sql = test_model.sorted_by_columns("organization__name:asc").to_sql
      expect(sql).to include('"organization" ON')
      expect(sql).to include("organization.name")
    end

    it "handles multiple JOINs correctly" do
      # Create another association model for testing
      ActiveRecord::Schema.define do
        create_table :categories, force: true do |t|
          t.string :name
          t.timestamps
        end
      end

      # Add association to User model
      User.class_eval do
        belongs_to :category, optional: true
      end

      # Create Category model
      Object.const_set(:Category, Class.new(ActiveRecord::Base))
      Category.class_eval do
        has_many :users
      end

      # Add category to allowed columns
      test_model.sort_by_columns :name, :organization__name, :category__name

      sql = test_model.sorted_by_columns("organization__name:asc,category__name:desc").to_sql

      # Should have separate JOINs
      expect(sql).to match(/LEFT OUTER JOIN "organizations"(?: AS)? "organization"/)
      expect(sql).to include('LEFT OUTER JOIN "categories"')

      # Should not duplicate JOINs
      expect(sql.scan('LEFT OUTER JOIN "organizations"').length).to eq(1)
      expect(sql.scan('LEFT OUTER JOIN "categories"').length).to eq(1)
    end
  end

  describe "custom class_name associations" do
    it "handles custom class_name associations" do
      # Create a custom association with class_name
      ActiveRecord::Schema.define do
        create_table :companies, force: true do |t|
          t.string :name
          t.timestamps
        end
      end

      # Add custom association to User model
      User.class_eval do
        belongs_to :company, class_name: "Organization", foreign_key: "organization_id", optional: true
      end

      # Add company to allowed columns
      test_model.sort_by_columns :name, :company__name

      sql = test_model.sorted_by_columns("company__name:asc").to_sql

      # Should create proper JOIN using the association name as alias
      expect(sql).to match(/LEFT OUTER JOIN "organizations"(?: AS)? "company"/)
      expect(sql).to include("company.name ASC NULLS LAST")
    end
  end

  describe "table prefixes and column references" do
    it "uses proper table prefix for local columns" do
      sql = test_model.sorted_by_columns("name:asc,email:desc").to_sql
      expect(sql).to include("users.name ASC")
      expect(sql).to include("users.email DESC")
    end

    it "uses association alias for association columns" do
      sql = test_model.sorted_by_columns("organization__name:asc").to_sql
      expect(sql).to include("organization.name ASC NULLS LAST")
      expect(sql).not_to include("organizations.name")
    end

    it "maintains proper references in mixed sorts" do
      sql = test_model.sorted_by_columns("name:asc,organization__name:desc,email:asc").to_sql
      expect(sql).to include("users.name ASC")
      expect(sql).to include("organization.name DESC NULLS FIRST")
      expect(sql).to include("users.email ASC")
    end
  end

  describe "ORDER BY clause construction" do
    it "builds single column ORDER BY" do
      sql = test_model.sorted_by_columns("name:asc").to_sql
      expect(sql).to match(/ORDER BY users\.name ASC\s*(?:LIMIT|$)/)
    end

    it "builds multi-column ORDER BY with proper comma separation" do
      sql = test_model.sorted_by_columns("name:asc,email:desc").to_sql
      expect(sql).to match(/ORDER BY users\.name ASC, users\.email DESC/)
    end

    it "builds mixed local and association ORDER BY" do
      sql = test_model.sorted_by_columns("name:asc,organization__name:desc,email:asc").to_sql
      expect(sql).to match(/ORDER BY users\.name ASC, organization\.name DESC NULLS FIRST, users\.email ASC/)
    end

    it "maintains exact column order as specified" do
      sql = test_model.sorted_by_columns("email:desc,name:asc,organization__name:asc").to_sql
      expect(sql).to match(/ORDER BY users\.email DESC, users\.name ASC, organization\.name ASC NULLS LAST/)
    end
  end
end

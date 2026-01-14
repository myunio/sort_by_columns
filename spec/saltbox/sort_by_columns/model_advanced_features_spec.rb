# frozen_string_literal: true

require "rails_helper"

RSpec.describe Saltbox::SortByColumns::Model, "Advanced Features & Custom Scopes" do
  # Use the real User model from our Combustion app
  let(:test_model) { User }

  before do
    # Create test data
    @org_a = Organization.create!(name: "Alpha Corp")
    @org_b = Organization.create!(name: "Beta Inc")

    @user1 = User.create!(name: "Charlie", email: "charlie@example.com", organization: @org_b)
    @user2 = User.create!(name: "Alice", email: "alice@example.com", organization: @org_a)
    @user3 = User.create!(name: "Bob", email: "bob@example.com", organization: @org_a)
  end

  describe "Custom Scope Comprehensive Testing" do
    describe ".handle_custom_scope (private method)" do
      before do
        # Set up custom scope columns
        test_model.sort_by_columns :name, :c_full_name, :c_priority_score

        # Mock the custom scope methods
        allow(test_model).to receive(:sorted_by_full_name).and_return(test_model.order(:name))
        allow(test_model).to receive(:sorted_by_priority_score).and_return(test_model.order(:email))
      end

      context "strips c_ prefix correctly" do
        it "strips c_ prefix and calls correct method" do
          test_model.send(:handle_custom_scope, "c_full_name:asc")
          expect(test_model).to have_received(:sorted_by_full_name).with("asc")
        end

        it "strips c_ prefix for different custom scope" do
          test_model.send(:handle_custom_scope, "c_priority_score:desc")
          expect(test_model).to have_received(:sorted_by_priority_score).with("desc")
        end

        it "handles custom scope without direction" do
          test_model.send(:handle_custom_scope, "c_full_name")
          expect(test_model).to have_received(:sorted_by_full_name).with("asc")
        end

        it "handles custom scope with whitespace" do
          test_model.send(:handle_custom_scope, "  c_full_name:desc  ")
          expect(test_model).to have_received(:sorted_by_full_name).with("desc")
        end
      end

      context "calls correct scope method with direction" do
        it "calls method with asc direction" do
          test_model.send(:handle_custom_scope, "c_full_name:asc")
          expect(test_model).to have_received(:sorted_by_full_name).with("asc")
        end

        it "calls method with desc direction" do
          test_model.send(:handle_custom_scope, "c_full_name:desc")
          expect(test_model).to have_received(:sorted_by_full_name).with("desc")
        end

        it "defaults to asc when no direction specified" do
          test_model.send(:handle_custom_scope, "c_full_name")
          expect(test_model).to have_received(:sorted_by_full_name).with("asc")
        end

        it "normalizes invalid direction to asc" do
          test_model.send(:handle_custom_scope, "c_full_name:invalid")
          expect(test_model).to have_received(:sorted_by_full_name).with("asc")
        end
      end

      context "validates custom scope in allowed fields" do
        it "processes allowed custom scope" do
          result = test_model.send(:handle_custom_scope, "c_full_name:asc")
          expect(result).to be_a(ActiveRecord::Relation)
          expect(test_model).to have_received(:sorted_by_full_name).with("asc")
        end

        context "in development environment" do
          before { allow(Rails.env).to receive(:local?).and_return(true) }

          it "raises error for disallowed custom scope" do
            expect {
              test_model.send(:handle_custom_scope, "c_unauthorized:asc")
            }.to raise_error(ArgumentError, /disallowed sortable column/)
          end

          it "includes column name in error message" do
            expect {
              test_model.send(:handle_custom_scope, "c_restricted_scope:desc")
            }.to raise_error(ArgumentError, /c_restricted_scope/)
          end
        end

        context "in production environment" do
          before do
            allow(Rails.env).to receive(:local?).and_return(false)
            allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
          end

          it "logs warning and returns all relation for disallowed custom scope" do
            result = test_model.send(:handle_custom_scope, "c_unauthorized:asc")

            expect(Rails.logger).to have_received(:warn).with("SortByColumns ignoring disallowed column: c_unauthorized")
            expect(result).to be_a(ActiveRecord::Relation)
            expect(result.count).to eq(3)
          end
        end
      end

      context "prevents mixing with other columns" do
        context "in development environment" do
          before { allow(Rails.env).to receive(:local?).and_return(true) }

          it "raises error when custom scope is mixed with other columns" do
            expect {
              test_model.send(:handle_custom_scope, "c_full_name:asc,name:desc")
            }.to raise_error(ArgumentError, /does not support multiple columns/)
          end

          it "raises error with multiple custom scopes" do
            expect {
              test_model.send(:handle_custom_scope, "c_full_name:asc,c_priority_score:desc")
            }.to raise_error(ArgumentError, /does not support multiple columns/)
          end

          it "raises error with trailing comma" do
            expect {
              test_model.send(:handle_custom_scope, "c_full_name:asc,")
            }.to raise_error(ArgumentError, /does not support multiple columns/)
          end
        end

        context "in production environment" do
          before do
            allow(Rails.env).to receive(:local?).and_return(false)
            allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
          end

          it "logs critical warning and returns all relation" do
            result = test_model.send(:handle_custom_scope, "c_full_name:asc,name:desc")

            expect(Rails.logger).to have_received(:warn).with("SortByColumns ignoring all columns due to c_full_name:asc,name:desc")
            expect(result).to be_a(ActiveRecord::Relation)
            expect(result.count).to eq(3)
            expect(test_model).not_to have_received(:sorted_by_full_name)
          end
        end
      end

      context "handles missing scope methods gracefully" do
        before do
          test_model.sort_by_columns :name, :c_nonexistent_scope
        end

        context "in development environment" do
          before { allow(Rails.env).to receive(:local?).and_return(true) }

          it "raises error when scope method doesn't exist" do
            expect {
              test_model.send(:handle_custom_scope, "c_nonexistent_scope:asc")
            }.to raise_error(ArgumentError, /does not respond to 'sorted_by_nonexistent_scope'/)
          end

          it "includes model name in error message" do
            expect {
              test_model.send(:handle_custom_scope, "c_nonexistent_scope:asc")
            }.to raise_error(ArgumentError, /model #{test_model.name}/)
          end

          it "provides helpful scope definition suggestion" do
            expect {
              test_model.send(:handle_custom_scope, "c_nonexistent_scope:asc")
            }.to raise_error(ArgumentError, /scope :sorted_by_nonexistent_scope/)
          end
        end

        context "in production environment" do
          before do
            allow(Rails.env).to receive(:local?).and_return(false)
            allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
          end

          it "logs warning and returns all relation" do
            result = test_model.send(:handle_custom_scope, "c_nonexistent_scope:asc")

            expect(Rails.logger).to have_received(:warn).with("SortByColumns ignoring disallowed column: c_nonexistent_scope")
            expect(result).to be_a(ActiveRecord::Relation)
            expect(result.count).to eq(3)
          end
        end
      end

      context "handles scope method exceptions" do
        before do
          test_model.sort_by_columns :name, :c_problematic_scope
          allow(test_model).to receive(:respond_to?).with(:sorted_by_problematic_scope).and_return(true)
          allow(test_model).to receive(:sorted_by_problematic_scope).and_raise(StandardError, "Scope error")
        end

        it "allows scope method exceptions to propagate" do
          expect {
            test_model.send(:handle_custom_scope, "c_problematic_scope:asc")
          }.to raise_error(StandardError, "Scope error")
        end
      end

      context "handles edge cases" do
        it "handles empty string" do
          # Empty string should be handled by the main sorted_by_columns method
          # handle_custom_scope assumes non-empty input
          allow(Rails.env).to receive(:local?).and_return(false)
          allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))

          result = test_model.send(:handle_custom_scope, "c_")
          expect(result).to be_a(ActiveRecord::Relation)
          expect(result.count).to eq(3)
        end

        it "handles string with only whitespace" do
          # Whitespace-only strings should be handled by the main sorted_by_columns method
          # handle_custom_scope assumes non-empty input
          allow(Rails.env).to receive(:local?).and_return(false)
          allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))

          result = test_model.send(:handle_custom_scope, "c_:")
          expect(result).to be_a(ActiveRecord::Relation)
          expect(result.count).to eq(3)
        end

        it "handles string with just c_ prefix" do
          allow(Rails.env).to receive(:local?).and_return(false)
          allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))

          result = test_model.send(:handle_custom_scope, "c_")
          expect(result).to be_a(ActiveRecord::Relation)
          expect(result.count).to eq(3)
        end
      end
    end

    describe "custom scope integration" do
      before do
        # Define real custom scopes for testing
        test_model.class_eval do
          scope :sorted_by_full_name, ->(direction) {
            order("users.name #{direction.upcase}, users.email #{direction.upcase}")
          }

          scope :sorted_by_priority_score, ->(direction) {
            # Simulate a complex custom sort
            order("users.created_at #{direction.upcase}")
          }

          scope :sorted_by_organization_priority, ->(direction) {
            joins(:organization).order("organizations.name #{direction.upcase}")
          }
        end

        test_model.sort_by_columns :name, :c_full_name, :c_priority_score, :c_organization_priority
      end

      context "works with real model scopes" do
        it "calls real scope method and returns proper relation" do
          result = test_model.sorted_by_columns("c_full_name:asc")

          expect(result).to be_a(ActiveRecord::Relation)
          expect(result.count).to eq(3)

          # Verify the actual sorting works
          names = result.pluck(:name)
          expect(names).to eq(%w[Alice Bob Charlie])
        end

        it "handles descending order" do
          result = test_model.sorted_by_columns("c_full_name:desc")

          expect(result).to be_a(ActiveRecord::Relation)
          names = result.pluck(:name)
          expect(names).to eq(%w[Charlie Bob Alice])
        end

        it "works with complex custom scopes" do
          result = test_model.sorted_by_columns("c_priority_score:desc")

          expect(result).to be_a(ActiveRecord::Relation)
          expect(result.count).to eq(3)

          # Should be ordered by created_at desc
          created_times = result.pluck(:created_at)
          expect(created_times).to eq(created_times.sort.reverse)
        end

        it "works with scopes that use joins" do
          result = test_model.sorted_by_columns("c_organization_priority:asc")

          expect(result).to be_a(ActiveRecord::Relation)
          expect(result.count).to eq(3)

          # Should be ordered by organization name
          org_names = result.includes(:organization).map { |u| u.organization.name }
          expect(org_names).to eq(["Alpha Corp", "Alpha Corp", "Beta Inc"])
        end
      end

      context "passes direction parameter correctly" do
        it "passes asc direction" do
          allow(test_model).to receive(:sorted_by_full_name).and_return(test_model.all)

          test_model.sorted_by_columns("c_full_name:asc")
          expect(test_model).to have_received(:sorted_by_full_name).with("asc")
        end

        it "passes desc direction" do
          allow(test_model).to receive(:sorted_by_full_name).and_return(test_model.all)

          test_model.sorted_by_columns("c_full_name:desc")
          expect(test_model).to have_received(:sorted_by_full_name).with("desc")
        end

        it "normalizes invalid direction to asc" do
          allow(test_model).to receive(:sorted_by_full_name).and_return(test_model.all)

          test_model.sorted_by_columns("c_full_name:invalid")
          expect(test_model).to have_received(:sorted_by_full_name).with("asc")
        end
      end

      context "returns proper ActiveRecord::Relation" do
        it "returns chainable relation" do
          result = test_model.sorted_by_columns("c_full_name:asc")

          expect(result).to be_a(ActiveRecord::Relation)
          expect(result.respond_to?(:where)).to be true
          expect(result.respond_to?(:limit)).to be true
          expect(result.respond_to?(:includes)).to be true
        end

        it "can be chained with other scopes" do
          result = test_model.sorted_by_columns("c_full_name:asc").where("name LIKE ?", "A%")

          expect(result).to be_a(ActiveRecord::Relation)
          expect(result.count).to eq(1)
          expect(result.first.name).to eq("Alice")
        end

        it "can be chained with includes" do
          result = test_model.sorted_by_columns("c_full_name:asc").includes(:organization)

          expect(result).to be_a(ActiveRecord::Relation)
          expect(result.count).to eq(3)

          # Verify association is loaded
          user = result.first
          expect(user.association(:organization)).to be_loaded
        end
      end
    end
  end

  describe "Standard Column Processing" do
    describe ".process_standard_columns (private method)" do
      before do
        test_model.sort_by_columns :name, :email, :created_at, :organization__name
      end

      context "correctly splits and parses column specifications" do
        it "processes single column" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "name:asc")

          expect(includes_needed).to eq([])
          expect(order_fragments).to eq(["users.name ASC"])
        end

        it "processes multiple columns" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "name:asc,email:desc")

          expect(includes_needed).to eq([])
          expect(order_fragments).to eq(["users.name ASC", "users.email DESC"])
        end

        it "processes mixed column types" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "name:asc,organization__name:desc")

          expect(includes_needed).to eq([:organization])
          expect(order_fragments).to eq(["users.name ASC", "organization.name DESC NULLS FIRST"])
        end

        it "handles columns without direction" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "name,email")

          expect(includes_needed).to eq([])
          expect(order_fragments).to eq(["users.name ASC", "users.email ASC"])
        end

        it "handles mixed directions" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "name:desc,email:asc")

          expect(includes_needed).to eq([])
          expect(order_fragments).to eq(["users.name DESC", "users.email ASC"])
        end

        it "handles whitespace around specifications" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "  name:asc  ,  email:desc  ")

          expect(includes_needed).to eq([])
          expect(order_fragments).to eq(["users.name ASC", "users.email DESC"])
        end
      end

      context "builds includes array for associations" do
        it "adds single association to includes" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "organization__name:asc")

          expect(includes_needed).to eq([:organization])
          expect(order_fragments).to eq(["organization.name ASC NULLS LAST"])
        end

        it "adds multiple associations to includes" do
          # Create another association for testing
          ActiveRecord::Schema.define do
            create_table :departments, force: true do |t|
              t.string :name
              t.timestamps
            end
          end

          User.class_eval do
            belongs_to :department, optional: true
          end

          Object.const_set(:Department, Class.new(ActiveRecord::Base))
          Department.class_eval do
            has_many :users
          end

          test_model.sort_by_columns :name, :organization__name, :department__name

          includes_needed, order_fragments = test_model.send(:process_standard_columns, "organization__name:asc,department__name:desc")

          expect(includes_needed).to eq([:organization, :department])
          expect(order_fragments).to eq(["organization.name ASC NULLS LAST", "department.name DESC NULLS FIRST"])
        end

        it "doesn't add duplicate associations" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "organization__name:asc,organization__name:desc")

          expect(includes_needed).to eq([:organization])
          expect(order_fragments).to eq(["organization.name ASC NULLS LAST", "organization.name DESC NULLS FIRST"])
        end
      end

      context "builds order fragments array" do
        it "builds fragments for standard columns" do
          _, order_fragments = test_model.send(:process_standard_columns, "name:asc,email:desc")

          expect(order_fragments).to be_an(Array)
          expect(order_fragments.length).to eq(2)
          expect(order_fragments).to eq(["users.name ASC", "users.email DESC"])
        end

        it "builds fragments for association columns" do
          _, order_fragments = test_model.send(:process_standard_columns, "organization__name:asc")

          expect(order_fragments).to be_an(Array)
          expect(order_fragments.length).to eq(1)
          expect(order_fragments).to eq(["organization.name ASC NULLS LAST"])
        end

        it "maintains order of fragments" do
          _, order_fragments = test_model.send(:process_standard_columns, "email:desc,name:asc,organization__name:desc")

          expect(order_fragments).to eq([
            "users.email DESC",
            "users.name ASC",
            "organization.name DESC NULLS FIRST"
          ])
        end

        it "handles empty result when no valid columns" do
          allow(Rails.env).to receive(:local?).and_return(false)
          allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))

          includes_needed, order_fragments = test_model.send(:process_standard_columns, "invalid1:asc,invalid2:desc")

          expect(order_fragments).to eq([])
          expect(includes_needed).to eq([])
        end
      end

      context "skips disallowed columns appropriately" do
        context "in production environment" do
          before do
            allow(Rails.env).to receive(:local?).and_return(false)
            allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
          end

          it "skips disallowed columns but processes allowed ones" do
            _, order_fragments = test_model.send(:process_standard_columns, "name:asc,invalid_column:desc,email:asc")

            expect(order_fragments).to eq(["users.name ASC", "users.email ASC"])
            expect(Rails.logger).to have_received(:warn).with("SortByColumns ignoring disallowed column: invalid_column")
          end

          it "skips multiple disallowed columns" do
            _, order_fragments = test_model.send(:process_standard_columns, "invalid1:asc,name:desc,invalid2:asc")

            expect(order_fragments).to eq(["users.name DESC"])
            expect(Rails.logger).to have_received(:warn).twice
          end

          it "handles all disallowed columns" do
            includes_needed, order_fragments = test_model.send(:process_standard_columns, "invalid1:asc,invalid2:desc")

            expect(order_fragments).to eq([])
            expect(includes_needed).to eq([])
            expect(Rails.logger).to have_received(:warn).twice
          end
        end

        context "in development environment" do
          before { allow(Rails.env).to receive(:local?).and_return(true) }

          it "raises error for disallowed columns" do
            expect {
              test_model.send(:process_standard_columns, "name:asc,invalid_column:desc")
            }.to raise_error(ArgumentError, /disallowed sortable column.*invalid_column/m)
          end
        end
      end

      context "handles mixed valid/invalid columns" do
        before do
          allow(Rails.env).to receive(:local?).and_return(false)
          allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
        end

        it "processes valid columns and logs warnings for invalid ones" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "invalid1:asc,name:desc,invalid2:asc,email:asc,organization__name:desc")

          expect(order_fragments).to eq([
            "users.name DESC",
            "users.email ASC",
            "organization.name DESC NULLS FIRST"
          ])
          expect(includes_needed).to eq([:organization])
          expect(Rails.logger).to have_received(:warn).twice
        end

        it "handles valid associations mixed with invalid columns" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "invalid1:asc,organization__name:desc,invalid2:asc")

          expect(order_fragments).to eq(["organization.name DESC NULLS FIRST"])
          expect(includes_needed).to eq([:organization])
          expect(Rails.logger).to have_received(:warn).twice
        end
      end

      context "handles edge cases" do
        it "handles empty string" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "")

          expect(includes_needed).to eq([])
          expect(order_fragments).to eq([])
        end

        it "handles string with only commas" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, ",,,")

          expect(includes_needed).to eq([])
          expect(order_fragments).to eq([])
        end

        it "handles string with empty column specifications" do
          includes_needed, order_fragments = test_model.send(:process_standard_columns, "name:asc,,email:desc")

          expect(includes_needed).to eq([])
          expect(order_fragments).to eq(["users.name ASC", "users.email DESC"])
        end

        it "handles malformed column specifications" do
          allow(Rails.env).to receive(:local?).and_return(false)
          allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))

          _, order_fragments = test_model.send(:process_standard_columns, "name:asc,::invalid::,email:desc")

          expect(order_fragments).to eq(["users.name ASC", "users.email DESC"])
        end
      end
    end
  end
end

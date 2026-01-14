# frozen_string_literal: true

# Only define shared examples if RSpec is properly loaded
if defined?(RSpec) && RSpec.respond_to?(:shared_examples)
  RSpec.shared_examples "sortable by columns" do |options|
    # factory = described_class.model_name.param_key.to_sym

    # Specify one ore more allowed columns defined on the described class
    allowed_columns = options[:allowed_columns].map(&:to_sym) || [:name]

    # Specify a disallowed column to test that it is ignored
    disallowed_column = options[:disallowed_column].to_sym

    # Specify an associated column (optional) as a hash with the fields: name and
    # expected_sql e.g. {name: :region__name, expected_sql: "regions.name"}
    associated_column = options[:associated_column]&.with_indifferent_access

    # Get the model table name
    model_table = described_class.table_name

    it { should include_module(Saltbox::SortByColumns::Model) }

    describe "allowed columns" do
      it "adds the columns to the allowed list" do
        expect(described_class.column_sortable_allowed_fields).to include(*allowed_columns)
      end

      it "generates the ORDER BY statement" do
        sql = described_class.sorted_by_columns("#{allowed_columns[0]}:asc").to_sql

        expect(sql).to match(/#{model_table}\.#{allowed_columns[0]} ASC/)
      end
    end

    describe "disallowed columns" do
      context "in non-local environment" do
        before do
          allow(Rails.env).to receive(:local?).and_return(false)
        end

        it "does not add the column to the allowed list" do
          expect(described_class.column_sortable_allowed_fields).not_to include(disallowed_column)
        end

        it "ignores a disallowed column and logs it" do
          expect(Rails.logger).to receive(:warn).with(/ignoring disallowed column/)

          described_class.sorted_by_columns("#{disallowed_column}:asc")
        end

        it "does not throw an error when a disallowed column is provided" do
          expect { described_class.sorted_by_columns("#{disallowed_column}:asc") }.not_to raise_error
        end

        it "does not generate the ORDER BY statement" do
          sql = described_class.sorted_by_columns("#{disallowed_column}:asc").to_sql

          expect(sql).not_to match(/#{disallowed_column} ASC/)
        end
      end

      context "in local environment" do
        it "throws an error when a disallowed column is provided" do
          allow(Rails.env).to receive(:local?).and_return(true)

          expect {
            described_class.sorted_by_columns("#{disallowed_column}:asc")
          }.to raise_error(ArgumentError)
        end
      end
    end

    describe "single local column sorting" do
      it "sorts by a single column in ascending order" do
        sql = described_class.sorted_by_columns("#{allowed_columns[0]}:asc").to_sql
        expect(sql).to match(/#{model_table}\.#{allowed_columns[0]} ASC/)
      end

      it "sorts by ascending order by default" do
        sql = described_class.sorted_by_columns(allowed_columns[0].to_s).to_sql
        expect(sql).to match(/#{model_table}\.#{allowed_columns[0]} ASC/)
      end

      it "sorts by a single column in descending order" do
        sql = described_class.sorted_by_columns("#{allowed_columns[0]}:desc").to_sql
        expect(sql).to match(/#{model_table}\.#{allowed_columns[0]} DESC/)
      end
    end

    describe "multi local column sorting", unless: (allowed_columns.length < 2) do
      it "sorts by multiple columns in ascending/descending order" do
        sql = described_class.sorted_by_columns("#{allowed_columns[0]}:asc,#{allowed_columns[1]}:desc").to_sql
        expect(sql).to match(/#{model_table}\.#{allowed_columns[0]} ASC, #{model_table}\.#{allowed_columns[1]} DESC/)
      end
    end

    describe "checking reflect_on_association" do
      let(:non_existent_assoc) { :not_a_real_association__column }

      before do
        # Add a column with an association that doesn't actually exist to the allowed list
        described_class.sort_by_columns(non_existent_assoc, *allowed_columns)

        # Mock the reflect_on_association method to explicitly check our fake association
        allow(described_class).to receive(:reflect_on_association).and_call_original
        allow(described_class).to receive(:reflect_on_association).with(:not_a_real_association).and_return(nil)
      end

      after do
        # Reset the allowed columns
        described_class.sort_by_columns(*allowed_columns)
      end

      it "checks if associations exist" do
        expect(described_class).to receive(:reflect_on_association).with(:not_a_real_association)

        # This line doesn't matter as much for the test - we're just verifying the method is called
        begin
          described_class.sorted_by_columns("#{non_existent_assoc}:asc")
        rescue
          nil
        end
      end

      it "skips invalid associations and continues with valid columns", unless: allowed_columns.empty? do
        # Test that an invalid association is skipped (with next) and the code proceeds to valid columns
        allow(Rails.env).to receive(:local?).and_return(false)

        # The warning format matches what the actual code logs
        expect(Rails.logger).to receive(:warn).with(/ignoring disallowed column: not_a_real_association/)

        # Sort by both invalid association and valid column
        sort_spec = "#{non_existent_assoc}:asc,#{allowed_columns[0]}:desc"
        sql = described_class.sorted_by_columns(sort_spec).to_sql

        # The SQL should still include the valid column
        expect(sql).to match(/#{model_table}\.#{allowed_columns[0]} DESC/)
        # But not the invalid association
        expect(sql).not_to include("not_a_real_association")
      end

      it "returns unmodified relation when all columns are invalid" do
        allow(Rails.env).to receive(:local?).and_return(false)

        # Only use the invalid association for sorting
        sql_before = described_class.all.to_sql
        sql_after = described_class.sorted_by_columns("#{non_existent_assoc}:asc").to_sql

        # The SQL should be the same (no ORDER BY clause added)
        expect(sql_after).to eq(sql_before)
      end
    end

    describe "association sorting", if: associated_column do
      let(:association_name) { associated_column[:name].to_s.split("__").first }

      before do
        # Make sure the association column is in the allowed list
        current_allowed = described_class.column_sortable_allowed_fields
        unless current_allowed.include?(associated_column[:name].to_sym)
          described_class.sort_by_columns(associated_column[:name].to_sym, *current_allowed)
        end
      end

      it "sorts by an associated column in ascending order" do
        sql = described_class.sorted_by_columns("#{associated_column[:name]}:asc").to_sql
        # Use association name (singular) instead of table name (plural)
        expect(sql).to include("#{association_name}.#{associated_column[:name].to_s.split("__").last} ASC")
        expect(sql).to include("NULLS LAST")
      end

      it "sorts by an associated column in descending order" do
        sql = described_class.sorted_by_columns("#{associated_column[:name]}:desc").to_sql
        # Use association name (singular) instead of table name (plural)
        expect(sql).to include("#{association_name}.#{associated_column[:name].to_s.split("__").last} DESC")
        expect(sql).to include("NULLS FIRST")
      end

      it "sorts a mixture of associated and local columns" do
        sql = described_class
          .sorted_by_columns("#{associated_column[:name]}:asc,#{allowed_columns[0]}:desc")
          .to_sql

        column_name = associated_column[:name].to_s.split("__").last
        expect(sql).to include("#{association_name}.#{column_name} ASC")
        expect(sql).to include("#{model_table}.#{allowed_columns[0]} DESC")
      end

      after do
        # Reset to original allowed columns if needed
        if described_class.column_sortable_allowed_fields.include?(associated_column[:name].to_sym) &&
            !allowed_columns.include?(associated_column[:name].to_sym)
          described_class.sort_by_columns(*allowed_columns)
        end
      end
    end

    describe 'columns with custom scopes (i.e. starting with "c_")' do
      before do
        # Define a custom scope on the described class and add it to
        # the allowed columns. NOTE: this scope remains for the duration of the
        # test suite.
        described_class.define_singleton_method(:sorted_by_foo) do |direction|
          "sorted by foo #{direction}"
        end
        described_class.sort_by_columns :c_foo, *allowed_columns
      end

      it "calls a custom scope when the allowed field is prefixed by c_" do
        expect(described_class).to receive(:sorted_by_foo).with("desc")

        described_class.sorted_by_columns("c_foo:desc")
      end

      context "with multiple columns" do
        context "in non-local environment" do
          before do
            allow(Rails.env).to receive(:local?).and_return(false)
          end

          it "does not allow multiple comma-separated columns" do
            expect(described_class).not_to receive(:sorted_by_foo)

            described_class.sorted_by_columns("c_foo:desc,name:desc")
          end

          it "logs a warning" do
            allow(Rails.env).to receive(:development?).and_return(false)

            expect(Rails.logger).to receive(:warn).with(/ignoring/)

            described_class.sorted_by_columns("c_foo:desc,name:desc")
          end
        end

        context "in local environment" do
          it "throws an error" do
            allow(Rails.env).to receive(:local?).and_return(true)

            expect {
              described_class.sorted_by_columns("c_foo:desc,name:desc")
            }.to raise_error(ArgumentError)
          end
        end
      end

      context "with disallowed column" do
        context "in non-local environment" do
          before do
            allow(Rails.env).to receive(:local?).and_return(false)
          end

          it "ignores the column and logs it" do
            expect(Rails.logger).to receive(:warn).with(/ignoring disallowed column/)

            described_class.sorted_by_columns("c_bar:asc")
          end

          it "does not throw an error" do
            expect { described_class.sorted_by_columns("c_bar:desc") }.not_to raise_error
          end
        end

        context "in local environment" do
          it "throws an error" do
            allow(Rails.env).to receive(:local?).and_return(true)

            expect { described_class.sorted_by_columns("c_bar:asc") }.to raise_error(ArgumentError)
          end
        end
      end

      after do
        # Reset the allowed columns
        described_class.sort_by_columns(*allowed_columns)
      end
    end

    describe "association table aliases" do
      # Only run this test if we have an association column to test with
      if associated_column
        let(:association_name) { associated_column[:name].to_s.split("__").first }

        before do
          # Make sure the association column is in the allowed list
          current_allowed = described_class.column_sortable_allowed_fields
          unless current_allowed.include?(associated_column[:name].to_sym)
            described_class.sort_by_columns(associated_column[:name].to_sym, *current_allowed)
          end
        end

        it "uses association name as the table alias in the SQL query" do
          sql = described_class.sorted_by_columns("#{associated_column[:name]}:asc").to_sql

          # The SQL should use the association name as the table alias
          expect(sql).to include("LEFT OUTER JOIN")
          expect(sql).to include("\"#{association_name}\" ON")
          expect(sql).to include("ORDER BY #{association_name}.")
        end

        after do
          # Reset to original allowed columns if needed
          if described_class.column_sortable_allowed_fields.include?(associated_column[:name].to_sym) &&
              !allowed_columns.include?(associated_column[:name].to_sym)
            described_class.sort_by_columns(*allowed_columns)
          end
        end
      end
    end
  end

  # Close the RSpec conditional block
end

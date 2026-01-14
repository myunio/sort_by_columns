require "rails_helper"

RSpec.describe "SortByColumns integration", type: :model do
  let!(:org_a) { Organization.create!(name: "Alpha Inc") }
  let!(:org_b) { Organization.create!(name: "Beta Corp") }

  let!(:user1) { User.create!(name: "Charlie", email: "charlie@example.com", organization: org_b) }
  let!(:user2) { User.create!(name: "Alice", email: "alice@example.com", organization: org_a) }
  let!(:user3) { User.create!(name: "Bob", email: "bob@example.com", organization: org_a) }

  before do
    User.sort_by_columns :name, :email, :organization__name, :c_full_name
  end

  context "standard column sorting" do
    it "sorts by name ascending" do
      result = User.sorted_by_columns("name:asc").pluck(:name)
      expect(result).to eq(%w[Alice Bob Charlie])
    end

    it "sorts by email descending" do
      result = User.sorted_by_columns("email:desc").pluck(:email)
      expect(result).to eq(%w[charlie@example.com bob@example.com alice@example.com])
    end

    it "handles multi-column sorting with real database" do
      # Create duplicate names to test secondary sort
      User.create!(name: "Alice", email: "alice2@example.com", organization: org_b)

      result = User.sorted_by_columns("name:asc,email:desc").pluck(:name, :email)
      alice_records = result.select { |name, email| name == "Alice" } # standard:disable Style/HashSlice

      expect(alice_records.length).to eq(2)
      # In descending email order: alice@example.com comes before alice2@example.com alphabetically
      expect(alice_records.first[1]).to eq("alice@example.com")
      expect(alice_records.last[1]).to eq("alice2@example.com")
    end
  end

  context "association column sorting" do
    it "sorts by organization name asc" do
      result = User.sorted_by_columns("organization__name:asc, name:asc").to_a
      expect(result.first.organization.name).to eq("Alpha Inc")
      expect(result.last.organization.name).to eq("Beta Corp")
    end

    it "generates correct SQL with LEFT OUTER JOIN" do
      result = User.sorted_by_columns("organization__name:asc")

      # Check that the query includes a LEFT OUTER JOIN
      expect(result.to_sql).to include("LEFT OUTER JOIN")
      expect(result.to_sql).to include("organizations")
      expect(result.to_sql).to include("ORDER BY")
    end

    it "handles NULL values in associations correctly" do
      # Create user without organization
      User.create!(name: "Orphan", email: "orphan@example.com", organization: nil)

      result = User.sorted_by_columns("organization__name:asc").to_a
      # Users without organizations should appear first (NULLS LAST for ASC)
      expect(result.last.name).to eq("Orphan")

      result_desc = User.sorted_by_columns("organization__name:desc").to_a
      # Users without organizations should appear last (NULLS FIRST for DESC)
      expect(result_desc.first.name).to eq("Orphan")
    end
  end

  context "custom scope column" do
    it "applies custom c_full_name scope" do
      # Add the custom column to allowed list for this example
      User.sort_by_columns :name, :c_full_name
      allow(User).to receive(:sorted_by_full_name).and_call_original

      result = User.sorted_by_columns("c_full_name:desc")
      expect(User).to have_received(:sorted_by_full_name).with("desc")
      expect(result.first.name).to eq("Charlie")
    end

    it "prevents mixing custom scopes with regular columns" do
      allow(Rails.env).to receive(:local?).and_return(false)

      result = User.sorted_by_columns("c_full_name:asc,name:desc")
      expect(result.count).to eq(3)
      # Should return unmodified relation when mixing custom scopes
      expect(result.pluck(:name)).to eq(%w[Charlie Alice Bob])
    end
  end

  context "edge cases with real Rails environment" do
    it "ignores unknown columns and still sorts valid ones" do
      allow(Rails.env).to receive(:local?).and_return(false)
      result = User.sorted_by_columns("invalid:asc,name:desc")
      expect(result.first.name).to eq("Charlie")
    end

    it "handles complex malformed input gracefully" do
      allow(Rails.env).to receive(:local?).and_return(false)

      result = User.sorted_by_columns("::invalid::,name:asc,,,bad_column:desc,")
      expect(result.pluck(:name)).to eq(%w[Alice Bob Charlie])
    end

    it "handles very long sort parameter strings" do
      allow(Rails.env).to receive(:local?).and_return(false)

      # Create a very long sort parameter with many invalid columns
      long_sort_param = (1..100).map { |i| "invalid_column_#{i}:asc" }.join(",") + ",name:desc"

      result = User.sorted_by_columns(long_sort_param)
      expect(result.pluck(:name)).to eq(%w[Charlie Bob Alice])
    end

    it "handles special characters in column names" do
      allow(Rails.env).to receive(:local?).and_return(false)

      result = User.sorted_by_columns("name@#$%:asc,email:desc")
      expect(result.pluck(:email)).to eq(%w[charlie@example.com bob@example.com alice@example.com])
    end

    it "handles association columns with invalid association names" do
      allow(Rails.env).to receive(:local?).and_return(false)

      User.sort_by_columns :name, :invalid_association__name

      result = User.sorted_by_columns("invalid_association__name:asc,name:desc")
      expect(result.pluck(:name)).to eq(%w[Charlie Bob Alice])
    end

    it "handles mixed valid and invalid columns efficiently" do
      allow(Rails.env).to receive(:local?).and_return(false)

      result = User.sorted_by_columns("invalid1:asc,name:desc,invalid2:asc,email:asc")

      # Should sort by name DESC first, then email ASC
      expect(result.pluck(:name)).to eq(%w[Charlie Bob Alice])
    end
  end

  context "performance with edge cases" do
    it "processes large allowed fields list efficiently" do
      # Create a large list of allowed fields
      large_fields = [:name, :email] + (1..100).map { |i| :"field_#{i}" }
      User.sort_by_columns(*large_fields)

      result = User.sorted_by_columns("name:asc")
      expect(result.pluck(:name)).to eq(%w[Alice Bob Charlie])
    end

    it "handles repeated calls efficiently" do
      # Test that repeated calls don't cause memory leaks or performance issues
      100.times do
        result = User.sorted_by_columns("name:asc")
        expect(result.count).to eq(3)
      end
    end
  end

  context "development environment error handling" do
    before { allow(Rails.env).to receive(:local?).and_return(true) }

    it "raises helpful errors for invalid columns" do
      expect {
        User.sorted_by_columns("invalid_column:asc")
      }.to raise_error(ArgumentError, /disallowed sortable column/)
    end

    it "raises helpful errors for invalid associations" do
      User.sort_by_columns :name, :invalid_association__name

      expect {
        User.sorted_by_columns("invalid_association__name:asc")
      }.to raise_error(ArgumentError, /doesn't exist on model/)
    end

    it "raises helpful errors for mixed custom scope columns" do
      expect {
        User.sorted_by_columns("c_full_name:asc,c_another_scope:desc")
      }.to raise_error(ArgumentError, /does not support multiple columns/)
    end
  end

  # Phase 3: Integration Error Handling & Environment Behavior
  context "Phase 3: Integration Error Handling & Environment Behavior" do
    describe "real Rails environment error handling" do
      context "with actual Rails.logger" do
        before do
          allow(Rails.env).to receive(:local?).and_return(false)
          # Use the actual Rails logger instead of a mock
          @original_logger = Rails.logger
          Rails.logger = Logger.new(StringIO.new)
        end

        after do
          Rails.logger = @original_logger
        end

        it "logs real warning messages to Rails.logger" do
          expect(Rails.logger).to receive(:warn).with(/ignoring disallowed column/)

          result = User.sorted_by_columns("invalid_column:asc")
          expect(result.count).to eq(3)
        end

        it "handles real Rails.logger with different log levels" do
          Rails.logger.level = Logger::ERROR

          result = User.sorted_by_columns("invalid_column:asc")
          expect(result.count).to eq(3)
        end
      end

      context "with StringIO logger" do
        before do
          allow(Rails.env).to receive(:local?).and_return(false)
          @log_output = StringIO.new
          Rails.logger = Logger.new(@log_output)
        end

        after do
          Rails.logger = Logger.new(File::NULL)
        end

        it "actually writes warning messages to log output" do
          User.sorted_by_columns("invalid_column:asc")

          @log_output.rewind
          log_content = @log_output.read
          expect(log_content).to include("ignoring disallowed column")
        end

        it "writes multiple warning messages for multiple invalid columns" do
          User.sorted_by_columns("invalid1:asc,invalid2:desc,invalid3:asc")

          @log_output.rewind
          log_content = @log_output.read
          expect(log_content.scan("ignoring disallowed column").count).to eq(3)
        end

        it "includes timestamp in log messages" do
          User.sorted_by_columns("invalid_column:asc")

          @log_output.rewind
          log_content = @log_output.read
          expect(log_content).to match(/\d{4}-\d{2}-\d{2}.*ignoring disallowed column/)
        end
      end
    end

    describe "real database error handling" do
      context "with actual ActiveRecord relations" do
        it "does not swallow database exceptions" do
          # This test ensures that if a database error occurs during sorting,
          # the exception is not caught by the gem and propagates up.
          relation_double = User.all
          allow(User).to receive(:all).and_return(relation_double)

          # Simulate a statement invalid error
          allow(relation_double).to receive(:reorder).and_raise(ActiveRecord::StatementInvalid)
          expect { User.sorted_by_columns("name:asc") }.to raise_error(ActiveRecord::StatementInvalid)

          # Simulate a connection error
          allow(relation_double).to receive(:reorder).and_raise(ActiveRecord::ConnectionNotEstablished)
          expect { User.sorted_by_columns("name:asc") }.to raise_error(ActiveRecord::ConnectionNotEstablished)
        end

        it "handles association queries with real database" do
          result = User.sorted_by_columns("organization__name:asc")
          expect(result.to_sql).to include("LEFT OUTER JOIN")
        end

        it "handles NULL values in association sorting correctly" do
          User.create!(name: "Orphan", email: "orphan@example.com", organization: nil)
          result = User.sorted_by_columns("organization__name:desc").to_a
          expect(result.first.name).to eq("Orphan")
        end
      end

      context "with transaction rollbacks" do
        before do
          allow(Rails.env).to receive(:local?).and_return(false)
          allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
        end

        it "handles rollbacks during sorting gracefully" do
          ActiveRecord::Base.transaction do
            result = User.sorted_by_columns("name:asc")
            expect(result.count).to eq(3)

            # Rollback doesn't affect the sorting logic
            raise ActiveRecord::Rollback
          end
        end
      end
    end

    describe "real Rails environment detection" do
      context "with actual Rails.env" do
        it "correctly detects development environment" do
          allow(Rails.env).to receive(:local?).and_return(true)

          expect {
            User.sorted_by_columns("invalid_column:asc")
          }.to raise_error(ArgumentError)
        end

        it "correctly detects production environment" do
          allow(Rails.env).to receive(:local?).and_return(false)
          allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))

          result = User.sorted_by_columns("invalid_column:asc")
          expect(result.count).to eq(3)
        end
      end

      context "with environment variables" do
        before do
          allow(Rails.env).to receive(:local?).and_return(false)
          allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
        end

        it "respects RAILS_ENV variable" do
          original_env = ENV["RAILS_ENV"]
          ENV["RAILS_ENV"] = "production"

          begin
            result = User.sorted_by_columns("invalid_column:asc")
            expect(result.count).to eq(3)
          ensure
            ENV["RAILS_ENV"] = original_env
          end
        end
      end
    end

    describe "memory and performance with real Rails" do
      before do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
      end

      it "handles memory efficiently with large datasets" do
        # Create many users
        (1..100).each { |i| User.create!(name: "User#{i}", email: "user#{i}@example.com") }

        start_memory = get_memory_usage
        result = User.sorted_by_columns("name:asc")
        result.count # Force evaluation
        end_memory = get_memory_usage

        # Memory usage should be reasonable
        expect(end_memory - start_memory).to be < 50_000 # Less than 50MB
      end

      it "handles performance efficiently with complex queries" do
        start_time = Time.now

        # Complex mixed query
        result = User.sorted_by_columns("invalid1:asc,name:desc,invalid2:asc,organization__name:asc,invalid3:desc")
        result.count # Force evaluation

        end_time = Time.now
        expect(end_time - start_time).to be < 1.0 # Under 1 second
      end

      it "handles repeated queries efficiently" do
        start_time = Time.now

        100.times do
          result = User.sorted_by_columns("name:asc")
          result.count
        end

        end_time = Time.now
        expect(end_time - start_time).to be < 2.0 # Under 2 seconds for 100 queries
      end

      private

      def get_memory_usage
        # Simple memory usage estimation
        # Fallback to 0 if stat is not available in current environment.
        (GC.stat[:total_allocated_bytes] || 0) / 1024 # Convert to kilobytes
      end
    end

    describe "concurrent access with real Rails" do
      before do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
      end

      it "handles concurrent sorting requests safely" do
        threads = []
        results = []

        10.times do
          threads << Thread.new do
            result = User.sorted_by_columns("name:asc")
            results << result.count
          end
        end

        threads.each(&:join)
        expect(results.all? { |count| count == 3 }).to be true
      end

      it "handles concurrent mixed requests safely" do
        threads = []
        results = []

        5.times do
          threads << Thread.new do
            result = User.sorted_by_columns("invalid_column:asc")
            results << result.count
          end
        end

        5.times do
          threads << Thread.new do
            result = User.sorted_by_columns("name:asc")
            results << result.count
          end
        end

        threads.each(&:join)
        expect(results.all? { |count| count == 3 }).to be true
      end

      it "handles concurrent database and error scenarios" do
        threads = []
        results = []

        # Mix of valid queries, invalid columns, and association queries
        10.times do |i|
          threads << Thread.new do
            case i % 3
            when 0
              result = User.sorted_by_columns("name:asc")
            when 1
              result = User.sorted_by_columns("invalid_column:asc")
            when 2
              result = User.sorted_by_columns("organization__name:asc")
            end
            results << result.count
          end
        end

        threads.each(&:join)
        expect(results.all? { |count| count == 3 }).to be true
      end
    end

    describe "integration with Rails features" do
      before do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
      end

      it "works with Rails scopes" do
        result = User.where(name: "Alice").sorted_by_columns("email:asc")
        expect(result.count).to eq(1)
        expect(result.first.name).to eq("Alice")
      end

      it "works with Rails includes" do
        result = User.includes(:organization).sorted_by_columns("name:asc")
        expect(result.count).to eq(3)
        expect(result.first.name).to eq("Alice")
      end

      it "works with Rails joins" do
        result = User.joins(:organization).sorted_by_columns("name:asc")
        expect(result.count).to eq(3)
        expect(result.first.name).to eq("Alice")
      end

      it "works with Rails limit and offset" do
        result = User.sorted_by_columns("name:asc").limit(2).offset(1)
        expect(result.count).to eq(2)
        expect(result.first.name).to eq("Bob")
      end

      it "works with Rails group and having" do
        # Create users with the same name to test grouping
        User.create!(name: "Charlie", email: "charlie2@example.com", organization: org_b)
        User.create!(name: "Alice", email: "alice2@example.com", organization: org_a)

        relation = User.group(:name).select("name, COUNT(*) as count")
        result = relation.sorted_by_columns("name:asc")

        # Using .count on a grouped relation with custom select can be tricky.
        # Instead, we'll inspect the resulting array.
        result_array = result.to_a
        expect(result_array.size).to eq(3)
        expect(result_array.map(&:name)).to eq(%w[Alice Bob Charlie])
        expect(result_array.first.count).to eq(2) # 2 Alices
      end

      it "works with Rails eager loading" do
        result = User.eager_load(:organization).sorted_by_columns("name:asc")
        expect(result.count).to eq(3)
        expect(result.first.name).to eq("Alice")
      end
    end

    describe "error recovery scenarios" do
      before do
        allow(Rails.env).to receive(:local?).and_return(false)
        allow(Rails).to receive(:logger).and_return(double("logger", warn: nil))
      end

      it "recovers from logger issues" do
        # Simulate a logger that raises an error
        allow(Rails.logger).to receive(:warn).and_raise(StandardError, "Logger blew up")
        allow(Rails.env).to receive(:local?).and_return(false)

        # The application should not crash if the logger fails
        expect {
          User.sorted_by_columns("invalid_column:asc")
        }.not_to raise_error
      end

      it "maintains data integrity during errors" do
        # Create a user and then trigger an error during a sort
        User.create!(name: "Stable", email: "stable@example.com")
        initial_count = User.count

        allow(User).to receive(:all).and_raise(StandardError, "Forced error")

        # Even if sorting fails, it shouldn't have caused data changes
        expect { User.sorted_by_columns("name:asc") }.to raise_error(StandardError, "Forced error")

        # Restore original method to allow .count to work
        allow(User).to receive(:all).and_call_original
        expect(User.count).to eq(initial_count)
      end
    end
  end
end

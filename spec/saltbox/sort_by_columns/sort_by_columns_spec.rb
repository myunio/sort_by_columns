# frozen_string_literal: true

RSpec.describe Saltbox::SortByColumns do
  it "has a version number" do
    expect(Saltbox::SortByColumns::VERSION).not_to be nil
  end

  it "defines the main module" do
    expect(Saltbox::SortByColumns).to be_a(Module)
  end

  it "defines the Model module" do
    expect(Saltbox::SortByColumns::Model).to be_a(Module)
  end

  it "defines the Controller module" do
    expect(Saltbox::SortByColumns::Controller).to be_a(Module)
  end
end

# Basic integration test - full functionality is tested in the consuming applications
RSpec.describe "SortByColumns integration" do
  it "loads without errors" do
    expect { require "sort_by_columns" }.not_to raise_error
  end

  it "defines the expected constants" do
    expect(defined?(Saltbox::SortByColumns::Model)).to eq("constant")
    expect(defined?(Saltbox::SortByColumns::Controller)).to eq("constant")
  end
end

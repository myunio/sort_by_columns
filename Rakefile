# frozen_string_literal: true

require "date"
require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec)

task default: [:spec, :standard]

desc "Run StandardRB linter"
task :standard do
  sh "standardrb"
end

desc "Run StandardRB linter with auto-fix"
task :standard_fix do
  sh "standardrb --fix"
end

desc "Build the gem"
task :build do
  sh "gem build sort_by_columns.gemspec"
end

desc "Install the gem locally"
task :install do
  sh "gem build sort_by_columns.gemspec"
  sh "gem install sort_by_columns-*.gem"
end

desc "Clean up build artifacts"
task :clean do
  sh "rm -f *.gem"
end

namespace :version do
  VERSION_FILE = "lib/saltbox/sort_by_columns/version.rb"
  CHANGELOG_FILE = "CHANGELOG.md"

  def calculate_new_version(type)
    require_relative VERSION_FILE
    current_version = Saltbox::SortByColumns::VERSION
    version_parts = current_version.split(".").map(&:to_i)

    case type
    when :patch
      version_parts[2] += 1
    when :minor
      version_parts[1] += 1
      version_parts[2] = 0
    when :major
      version_parts[0] += 1
      version_parts[1] = 0
      version_parts[2] = 0
    end

    [current_version, version_parts.join(".")]
  end

  def bump_version(type)
    current_version, new_version = calculate_new_version(type)
    tag_name = "v#{new_version}"

    puts "\n📦 Version Bump"
    puts "   Current: #{current_version}"
    puts "   New:     #{new_version} (#{type})"
    puts "   Tag:     #{tag_name}\n"

    # Check if git is clean
    unless system("git diff --quiet && git diff --cached --quiet")
      abort "Error: Working directory is not clean. Commit or stash changes first."
    end

    # Check if tag already exists
    if system("git rev-parse #{tag_name} >/dev/null 2>&1")
      abort "Error: Tag #{tag_name} already exists"
    end

    # Update version file
    version_content = File.read(VERSION_FILE)
    version_content.gsub!(/VERSION = ".*"/, %(VERSION = "#{new_version}"))
    File.write(VERSION_FILE, version_content)
    puts "✓ Updated #{VERSION_FILE}"

    # Update CHANGELOG.md
    if File.exist?(CHANGELOG_FILE)
      changelog_content = File.read(CHANGELOG_FILE)
      today = Date.today.strftime("%Y-%m-%d")
      new_entry = <<~CHANGELOG
        ## [#{new_version}] - #{today}

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

      CHANGELOG

      # Insert after the "and this project adheres to..." line
      changelog_content.sub!(/(#{Regexp.escape("and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).")}\n)/, "\\1\n#{new_entry}")
      File.write(CHANGELOG_FILE, changelog_content)
      puts "✓ Updated #{CHANGELOG_FILE} (please fill in the changelog entry)"
    end

    # Stage changes
    sh "git add #{VERSION_FILE}"
    sh "git add #{CHANGELOG_FILE}" if File.exist?(CHANGELOG_FILE)

    # Create commit
    commit_message = "Bump version to #{new_version}"
    sh "git commit -m '#{commit_message}'"

    # Create tag
    sh "git tag -a #{tag_name} -m 'Version #{new_version}'"
    puts "✓ Created git tag #{tag_name}"

    puts "\n✅ Version bumped successfully!"
    puts "\n📤 Next steps:"
    puts "   git push origin main"
    puts "   git push origin #{tag_name}"
    puts "\n   Or push everything at once:"
    puts "   git push origin main --follow-tags"
  end

  def preview_version(type)
    current_version, new_version = calculate_new_version(type)
    tag_name = "v#{new_version}"

    puts "\n📦 Version Bump Preview (#{type})"
    puts "   Current: #{current_version}"
    puts "   New:     #{new_version}"
    puts "   Tag:     #{tag_name}\n"
  end

  desc "Show current version"
  task :current do
    require_relative VERSION_FILE
    puts "Current version: #{Saltbox::SortByColumns::VERSION}"
  end

  namespace :bump do
    desc "Bump patch version (1.0.1 → 1.0.2)"
    task :patch do
      bump_version(:patch)
    end

    desc "Bump minor version (1.0.1 → 1.1.0)"
    task :minor do
      bump_version(:minor)
    end

    desc "Bump major version (1.0.1 → 2.0.0)"
    task :major do
      bump_version(:major)
    end
  end

  namespace :preview do
    desc "Preview patch version bump (1.0.1 → 1.0.2)"
    task :patch do
      preview_version(:patch)
    end

    desc "Preview minor version bump (1.0.1 → 1.1.0)"
    task :minor do
      preview_version(:minor)
    end

    desc "Preview major version bump (1.0.1 → 2.0.0)"
    task :major do
      preview_version(:major)
    end
  end
end

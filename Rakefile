# frozen_string_literal: true

require "bundler/gem_tasks"

# rake/testtask (not minitest/test_task) so `rake test` runs on every supported
# Ruby — minitest's own task class needs minitest 5.16+, which needs Ruby 2.6.
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

# RuboCop only installs on newer Rubies (see Gemfile); the default task degrades
# to test-only where it is absent.
begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
  task default: %i[test rubocop]
rescue LoadError
  task default: %i[test]
end

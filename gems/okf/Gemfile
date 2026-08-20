# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in okf.gemspec
gemspec

gem "rake", "~> 13.0"

# minitest 5.16 raised its floor to Ruby 2.6; 5.15 still runs the whole suite
# on 2.4/2.5, and bundler picks the right one per Ruby.
gem "minitest", ">= 5.15", "< 6"
gem "rack-test", "~> 2.1" # in-process HTTP testing for OKF::Server::App

# rack 3.1.20+/3.2.x declare Ruby >= 2.4 but crash there at require time (a
# `to_h { }` in rack/utils.rb needs 2.6); upstream fixed it on main and
# 3-1-stable right after the 3.1.21/3.2.6 releases (Apr 2026). Until a fixed
# rack ships, pin the old Rubies to the last release verified to load on 2.4
# (dev/CI only — the gemspec floor stays "rack >= 2.2").
gem "rack", "< 3.1.20" if RUBY_VERSION < "2.6"

# Tooling that has dropped old Rubies — the suite itself runs without them.
if RUBY_VERSION >= "2.7"
  gem "irb"
  gem "rubocop", "~> 1.21"
  gem "simplecov", "~> 0.22", require: false
end

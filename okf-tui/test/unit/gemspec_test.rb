# frozen_string_literal: true

require "test_helper"

# The declared `okf` floor is the one dependency claim nothing else can check.
# The Gemfile develops this gem against the kernel *checkout* next door, so
# every suite here runs against whatever `okf/lib/okf/version.rb` currently
# says — a surface published after the floor is used freely, stays green in CI,
# and fails on a host that resolved the floor instead. Worse here than in the
# MCP shell: okf's renames do not raise, they return nil (`area` → `top_dir`,
# `timestamp` → `generated_at`), so the failure is a wrong number on screen.
class OKF::TUI::GemspecTest < OKF::TUI::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)

  # The floor may lead the kernel (okf-tui can require an unreleased okf and
  # wait for it) but it may never lag. Equality is the normal state — the same
  # PR that bumps okf moves this line.
  test "the okf floor is not older than the kernel this suite resolves against" do
    assert_operator floor, :>=, Gem::Version.new(OKF::VERSION),
      "okf-tui.gemspec floors okf at #{floor}, but this suite runs against okf #{OKF::VERSION}: " \
      "the UI may already read surfaces #{floor} never published, and okf's renames read as nil " \
      "rather than raising. Move the floor to #{OKF::VERSION} (see the RELEASE OBLIGATION comment " \
      "in the gemspec)."
  end

  # The ceiling is what turns the next okf major's silent rename into a
  # resolution failure. A requirement that has lost it has lost that guard.
  test "the okf dependency keeps its major ceiling" do
    assert requirement.requirements.any? { |op, _| op == "<" },
      "okf-tui.gemspec declares no ceiling on okf: #{requirement}. The gemspec comment explains why " \
      "this one is earned — an okf major is where the silent drift comes from."
  end

  private

  def requirement
    dep = spec.dependencies.find { |d| d.name == "okf" }
    refute_nil dep, "okf-tui.gemspec declares no okf dependency"
    dep.requirement
  end

  def floor
    bound = requirement.requirements.find { |op, _| op == ">=" }
    refute_nil bound, "the okf dependency declares no `>=` floor: #{requirement}"
    bound.last
  end

  def spec
    # `spec.files` comes from `git ls-files` with chdir, so the working
    # directory it is evaluated in decides the answer.
    @spec ||= Dir.chdir(GEM_ROOT) { Gem::Specification.load(File.join(GEM_ROOT, "okf-tui.gemspec")) }
  end
end

# frozen_string_literal: true

require "test_helper"

# The declared `okf` floor is the one dependency claim nothing else can check.
# The Gemfile develops this gem against the kernel *checkout* next door, so
# every suite here runs against whatever `okf/lib/okf/version.rb` currently
# says — a surface published after the floor is used freely, stays green in CI,
# and fails on a host that resolved the floor instead.
#
# The consequence here is not a wrong number on a screen, it is a gate that
# stopped gating: this gem's policy is written in okf 2.0's §5 trust vocabulary,
# and against an older okf `Concept#trust_tier` is a NoMethodError inside a
# check whose crash the hook protocol reads as non-blocking.
class OKF::Pro::GemspecTest < OKF::Pro::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)

  # The floor may lead the kernel (okf-pro can require an unreleased okf and
  # wait for it) but it may never lag. Equality is the normal state — the same
  # PR that bumps okf moves this line.
  test "the okf floor is not older than the kernel this suite resolves against" do
    assert_operator floor, :>=, Gem::Version.new(OKF::VERSION),
      "okf-pro.gemspec floors okf at #{floor}, but this suite runs against okf #{OKF::VERSION}: " \
      "the gates may already read surfaces #{floor} never published. Move the floor to " \
      "#{OKF::VERSION} (see the RELEASE OBLIGATION comment in the gemspec)."
  end

  # The ceiling is what turns the next okf major's reclassified lint check into
  # a resolution failure instead of a gate that quietly stopped blocking on it.
  test "the okf dependency keeps its major ceiling" do
    assert requirement.requirements.any? { |op, _| op == "<" },
      "okf-pro.gemspec declares no ceiling on okf: #{requirement}. This gem pins a frozen " \
      "snapshot of okf's Linter::SEVERITIES; a major that moves a check between severities " \
      "changes what the gate blocks on."
  end

  private

  def requirement
    dep = spec.dependencies.find { |d| d.name == "okf" }
    refute_nil dep, "okf-pro.gemspec declares no okf dependency"
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
    @spec ||= Dir.chdir(GEM_ROOT) { Gem::Specification.load(File.join(GEM_ROOT, "okf-pro.gemspec")) }
  end
end

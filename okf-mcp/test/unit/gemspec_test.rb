# frozen_string_literal: true

require "test_helper"
require "mcp"

# The declared `okf` floor is the one dependency claim nothing else can check.
# The Gemfile develops this shell against the kernel *checkout* next door, so
# every suite here runs against whatever `okf/lib/okf/version.rb` currently
# says — a surface published after the floor is used freely, stays green in CI,
# and fails on a host that resolved the floor instead. That is a publish-time
# failure with no earlier symptom, which is what this test moves forward.
class OKF::MCP::GemspecTest < OKF::TestCase
  GEM_ROOT = File.expand_path("../..", __dir__)

  # The floor may lead the kernel (okf-mcp can require an unreleased okf and
  # wait for it) but it may never lag: a lagging floor admits a kernel this
  # code raises NameError against. Equality is the normal state — the same PR
  # that bumps okf moves this line.
  test "the okf floor is not older than the kernel this suite resolves against" do
    assert_operator floor, :>=, Gem::Version.new(OKF::VERSION),
      "okf-mcp.gemspec floors okf at #{floor}, but this suite runs against okf #{OKF::VERSION}: " \
      "the shell may already read surfaces #{floor} never published. Move the floor to " \
      "#{OKF::VERSION} (see the RELEASE OBLIGATION comment in the gemspec)."
  end

  # The same claim for the SDK, with the same shape of gap: the suite runs
  # against the locked `mcp`, so a wire behavior proven here — the modern
  # lifecycle, the streamed listen body — can be one the floor's oldest
  # admissible SDK never serves. The floor tracks what the suite proves;
  # the same PR that moves the lockfile moves the gemspec line.
  test "the mcp floor is not older than the SDK this suite resolves against" do
    assert_operator mcp_floor, :>=, Gem::Version.new(::MCP::VERSION),
      "okf-mcp.gemspec floors mcp at #{mcp_floor}, but this suite runs against mcp #{::MCP::VERSION}: " \
      "the tests may already prove behavior #{mcp_floor} never shipped. Move the floor to " \
      "#{::MCP::VERSION}."
  end

  private

  def floor
    dep = spec.dependencies.find { |d| d.name == "okf" }
    refute_nil dep, "okf-mcp.gemspec declares no okf dependency"
    requirement = dep.requirement.requirements.find { |op, _| op == ">=" }
    refute_nil requirement, "the okf dependency declares no `>=` floor: #{dep.requirement}"
    requirement.last
  end

  def mcp_floor
    dep = spec.dependencies.find { |d| d.name == "mcp" }
    refute_nil dep, "okf-mcp.gemspec declares no mcp dependency"
    # The mcp pin is pessimistic (`~>`), so the floor is that requirement's
    # version, not a separate `>=` line like okf's.
    requirement = dep.requirement.requirements.find { |op, _| op == "~>" }
    refute_nil requirement, "the mcp dependency declares no `~>` pin: #{dep.requirement}"
    requirement.last
  end

  def spec
    # `spec.files` comes from `git ls-files` with chdir, so the working
    # directory it is evaluated in decides the answer.
    @spec ||= Dir.chdir(GEM_ROOT) { Gem::Specification.load(File.join(GEM_ROOT, "okf-mcp.gemspec")) }
  end
end

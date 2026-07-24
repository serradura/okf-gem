# frozen_string_literal: true

require "test_helper"
require "json"
require "stringio"
require "tmpdir"
require "fileutils"
# The plugin lives at the repo root, one level above this gem — hence the third
# hop. Its two inputs are the gem's (the skill tree and the version), which is
# why its tests and its `rake plugin:sync` task stay here rather than moving up.
require_relative "../../../plugin/hooks/scripts/curate"

# The plugin's PostToolUse hook: gate (only markdown inside a bundle), detect
# (the okf CLI, injectable here), filter (bundle-wide errors + findings that
# concern the edited file), and degrade gracefully when the CLI is missing.
class OKF::PluginCurateTest < OKF::TestCase
  setup do
    @dir = Dir.mktmpdir("okf-curate-test")
    @root = File.join(@dir, "bundle")
    FileUtils.mkdir_p(File.join(@root, "concepts"))
    File.write(File.join(@root, "index.md"), "---\nokf_version: \"0.1\"\n---\n\n# Bundle\n")
    File.write(File.join(@root, "concepts", "index.md"), "# Concepts\n")
    File.write(File.join(@root, "concepts", "foo.md"), "---\ntype: Concept\n---\n\n# Foo\n")
  end

  teardown do
    FileUtils.remove_entry(@dir)
  end

  test "ignores an edit outside markdown" do
    assert_silent_run(file_path: File.join(@root, "app.rb"))
  end

  test "ignores a markdown edit outside a bundle" do
    File.write(File.join(@dir, "notes.md"), "# Notes\n")
    assert_silent_run(file_path: File.join(@dir, "notes.md"))
  end

  test "ignores an event without a file path" do
    out = run_hook({ "tool_input" => {} }, runner: never_called)
    assert_equal "", out
  end

  test "finds the bundle root above the edited file, past a nested index" do
    curate = OKF::PluginHook::Curate.new(runner: never_called)
    assert_equal @root, curate.bundle_root(File.join(@root, "concepts", "foo.md"))
    assert_nil curate.bundle_root(File.join(@dir, "notes.md"))
  end

  test "stays silent when the reports are clean" do
    out = run_hook(edit_event, runner: canned(validation: {}, lint: {}))
    assert_equal "", out
  end

  test "reports every conformance error plus the findings that concern the edited file" do
    validation = {
      "errors" => [ { "path" => "concepts/other.md", "message" => "missing non-empty `type`" } ],
      "warnings" => [
        { "path" => "concepts/foo.md", "message" => "broken link `./nope.md`" },
        { "path" => "concepts/other.md", "message" => "not for this edit" }
      ]
    }
    lint = { "findings" => [
      { "check" => "stub", "severity" => "info", "path" => "concepts/foo.md", "message" => "body has 12 chars" },
      { "check" => "missing_concept", "severity" => "info", "path" => "concepts/bars.md",
        "message" => "referenced by 2 link(s) across 1 concept(s) but does not exist",
        "metric" => { "references" => 2, "sources" => [ "concepts/foo" ] } },
      { "check" => "orphan", "severity" => "warn", "path" => "concepts/other.md", "message" => "not for this edit" },
      { "check" => "duplicate_title", "severity" => "info", "path" => nil, "message" => "bundle-wide, skipped" }
    ] }

    context = context_of(run_hook(edit_event, runner: canned(validation: validation, lint: lint)))
    assert_includes context, "1 error, 1 warning, 2 lint findings"
    assert_includes context, "✗ error concepts/other.md: missing non-empty `type`"
    assert_includes context, "! warn concepts/foo.md: broken link `./nope.md`"
    assert_includes context, "· lint/stub concepts/foo.md"
    assert_includes context, "· lint/missing_concept concepts/bars.md"
    assert_includes context, "Fix the error(s) before finishing"
    refute_includes context, "not for this edit"
    refute_includes context, "bundle-wide, skipped"
  end

  test "advisory tone when there are findings but no conformance error" do
    lint = { "findings" => [
      { "check" => "stale", "severity" => "warn", "path" => "concepts/foo.md", "message" => "older than the cutoff" }
    ] }
    context = context_of(run_hook(edit_event, runner: canned(validation: {}, lint: lint)))
    assert_includes context, "! lint/stale concepts/foo.md"
    assert_includes context, "Advisory curation debt"
  end

  test "caps the feedback and points at the curate playbook for the rest" do
    findings = (1..20).map do |i|
      { "check" => "stub", "severity" => "info", "path" => "concepts/foo.md", "message" => "finding #{i}" }
    end
    context = context_of(run_hook(edit_event, runner: canned(validation: {}, lint: { "findings" => findings })))
    assert_includes context, "… 8 more (run /okf:gem curate for the full report)"
  end

  # Written with an inner begin/ensure: `ensure` directly inside a do…end block
  # is Ruby 2.6+ syntax, and the tests run on 2.4 too.
  test "a missing okf CLI nags once per session, then stays silent" do
    session = "curate-test-#{Process.pid}-#{Time.now.to_f}"
    marker = File.join(Dir.tmpdir, "okf-plugin-#{session.gsub(/[^\w-]/, "_")}.notified")
    missing = ->(_verb, _root) { raise Errno::ENOENT, "okf" }

    begin
      first = run_hook(edit_event("session_id" => session), runner: missing)
      assert_includes JSON.parse(first)["systemMessage"], "/okf:gem"

      second = run_hook(edit_event("session_id" => session), runner: missing)
      assert_equal "", second
    ensure
      FileUtils.rm_f(marker)
    end
  end

  test "a CLI that emits garbage degrades to silence, not an error" do
    out = run_hook(edit_event, runner: ->(_verb, _root) { "rubbish, not JSON" })
    assert_equal "", out
  end

  test "OKF_CURATE_DISABLED silences the hook before it reaches the CLI" do
    with_env("OKF_CURATE_DISABLED" => "1") do
      assert_equal "", run_hook(edit_event, runner: never_called)
    end
  end

  test "an off spelling of OKF_CURATE_DISABLED leaves the hook on" do
    validation = { "errors" => [ { "path" => "concepts/foo.md", "message" => "boom" } ] }
    with_env("OKF_CURATE_DISABLED" => "false") do
      context = context_of(run_hook(edit_event, runner: canned(validation: validation, lint: {})))
      assert_includes context, "✗ error concepts/foo.md: boom"
    end
  end

  test "an okf-disable marker in the edited file silences curation for it" do
    File.write(File.join(@root, "concepts", "foo.md"),
      "---\ntype: Concept\n---\n\n<!-- okf-disable -->\n\n# Foo\n")
    assert_equal "", run_hook(edit_event, runner: never_called)
  end

  test "OKF_CURATE_QUIET drops the missing-CLI nudge" do
    missing = ->(_verb, _root) { raise Errno::ENOENT, "okf" }
    with_env("OKF_CURATE_QUIET" => "1") do
      out = run_hook(edit_event("session_id" => "quiet-#{Process.pid}"), runner: missing)
      assert_equal "", out
    end
  end

  private

  # Set env vars for the block and restore them after. A method-level begin/ensure
  # so it is safe on the 2.4 floor (ensure directly in a do…end block is 2.6+).
  def with_env(vars)
    saved = vars.keys.each_with_object({}) { |key, memo| memo[key] = ENV.fetch(key, nil) }
    vars.each { |key, value| ENV[key] = value }
    begin
      yield
    ensure
      saved.each { |key, value| ENV[key] = value }
    end
  end

  def edit_event(extra = {})
    { "tool_input" => { "file_path" => File.join(@root, "concepts", "foo.md") } }.merge(extra)
  end

  def run_hook(event, runner:)
    stdout = StringIO.new
    status = OKF::PluginHook::Curate.new(runner: runner).run(StringIO.new(JSON.generate(event)), stdout)
    assert_equal 0, status
    stdout.string
  end

  def context_of(output)
    JSON.parse(output).fetch("hookSpecificOutput").fetch("additionalContext")
  end

  # A gate test's runner: reaching the CLI at all means the gate failed.
  def never_called
    ->(_verb, _root) { flunk "the gate should have stopped before the CLI ran" }
  end

  # Canned CLI output, keyed by verb.
  def canned(validation:, lint:)
    ->(verb, _root) { JSON.generate(verb == "validate" ? validation : lint) }
  end

  def assert_silent_run(file_path:)
    out = run_hook({ "tool_input" => { "file_path" => file_path } }, runner: never_called)
    assert_equal "", out
  end
end

# frozen_string_literal: true

require "test_helper"

# The event is the only place this checker parses input it did not write, so
# it is the only place a malformed input can be mistaken for an innocent one.
# Every test below is really the same question: does an unreadable event say
# so, or does it look like a clean pass?
class EventTest < OKF::Pro::TestCase
  def test_parses_a_json_object
    e = OKF::Pro::Event.new('{"tool_name":"Write","cwd":"/tmp","tool_input":{"file_path":"/tmp/a.md"}}')

    refute e.parse_error?
    assert_equal "Write", e.tool_name
    assert_equal "/tmp", e.cwd
    assert_equal "/tmp/a.md", e.file_path
  end

  def test_empty_stdin_is_a_parse_error_not_an_empty_event
    e = OKF::Pro::Event.new("")

    assert e.parse_error?
    assert_match(/no event on stdin/, e.parse_error)
  end

  def test_whitespace_only_stdin_is_a_parse_error
    assert OKF::Pro::Event.new("   \n ").parse_error?
  end

  def test_malformed_json_is_a_parse_error
    e = OKF::Pro::Event.new('{"tool_input": {')

    assert e.parse_error?
    assert_match(/not parseable JSON/, e.parse_error)
  end

  # The regression that matters: the first draft rescued this into an empty
  # hash, every guard read an empty path, and the check passed — the `jq` hole
  # rebuilt in Ruby.
  def test_a_json_array_is_not_an_event
    e = OKF::Pro::Event.new('["not", "an", "object"]')

    assert e.parse_error?
    assert_match(/not a JSON object/, e.parse_error)
  end

  def test_missing_fields_do_not_raise
    e = OKF::Pro::Event.new("{}")

    refute e.parse_error?
    assert_equal "", e.tool_name
    assert_equal "", e.file_path
    assert_equal({}, e.tool_input)
    refute e.stop_hook_active?
  end

  def test_cwd_falls_back_to_the_working_directory
    assert_equal Dir.pwd, OKF::Pro::Event.new("{}").cwd
  end

  def test_non_hash_tool_input_is_ignored
    assert_equal({}, OKF::Pro::Event.new('{"tool_input":"nope"}').tool_input)
  end

  # Claude Code's Edit sends new_string. The shell shims only ever read
  # new_str, so the attestation guard could not refuse a real edit — it only
  # ever refused the synthetic JSON in its own drill.
  def test_added_text_reads_new_string
    assert_equal "hello", event(tool_input: { new_string: "hello" }).added_text
  end

  def test_added_text_reads_new_str
    assert_equal "hello", event(tool_input: { new_str: "hello" }).added_text
  end

  def test_added_text_reads_write_content
    assert_equal "hello", event(tool_input: { content: "hello" }).added_text
  end

  def test_added_text_reads_every_multiedit_edit
    e = event(tool_input: { edits: [ { new_string: "first" }, { new_str: "second" } ] })

    assert_includes e.added_text, "first"
    assert_includes e.added_text, "second"
  end

  def test_added_text_survives_a_malformed_edits_list
    assert_equal "", event(tool_input: { edits: "not a list" }).added_text
    assert_equal "", event(tool_input: { edits: [ "not a hash" ] }).added_text
  end

  # The guard's own input was a bypass: under a bare locale (common in CI
  # and git hooks) stdin arrives tagged US-ASCII, and a clean em dash in an
  # edit's new_string raised out of the first string operation — above the
  # dispatch rescue, exiting 1, which the hook protocol reads as
  # NON-BLOCKING. The event reader now gives stdin the same forced-UTF-8
  # scrub Pro.read_text gives files.
  def test_reads_an_event_the_locale_mistagged_as_ascii
    raw = %({"tool_name":"Edit","tool_input":{"new_string":"verified \u2014 by hand"}})
    assert raw.include?("\u2014"), "the fixture must carry real em-dash bytes, not an escape"
    e = OKF::Pro::Event.new(raw.dup.force_encoding("US-ASCII"))

    refute e.parse_error?
    assert_includes e.added_text, "verified"
  end

  def test_invalid_bytes_inside_a_string_are_scrubbed_not_raised
    e = OKF::Pro::Event.new(%({"tool_name":"Edit","tool_input":{"new_string":"a\xFFb"}}).b)

    refute e.parse_error?
    assert_equal "Edit", e.tool_name
  end

  def test_invalid_bytes_outside_the_json_are_a_parse_error_not_a_crash
    e = OKF::Pro::Event.new("\xFF\xFE not json".b)

    assert e.parse_error?
  end

  def test_a_frozen_input_does_not_raise
    refute OKF::Pro::Event.new('{"tool_name":"Write"}').parse_error?
  end

  def test_stop_hook_active_is_strictly_boolean_true
    assert event(stop_hook_active: true).stop_hook_active?
    refute event(stop_hook_active: "true").stop_hook_active?
    refute event.stop_hook_active?
  end
end

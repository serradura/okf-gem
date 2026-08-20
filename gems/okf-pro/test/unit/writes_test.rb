# frozen_string_literal: true

require "test_helper"

# The single seam every write verb funnels through, tested where a verb cannot
# reach it.
#
# `commit` is guard-then-write, in that order and nowhere else, so "refuses
# rather than writing" is a property of one method rather than a habit five of
# them share. Its refusal arm is unreachable from a fixture by construction —
# it fires only when a transform's own declared delta is wrong, which is the
# bug it exists to catch and not a state a bundle can be put into. It still has
# to be proven: "unreachable today" is how a guard rots into a `return`.
class WritesTest < OKF::Pro::TestCase
  test "commit refuses a mismatched claim and leaves the file untouched" do
    with_bundle do |b|
      path = File.join(b.bundle_path, "board.md")
      before = OKF::Pro.read_text(path)
      after = "#{before}- a line nobody declared\n"

      result = OKF::Pro::Writes.commit(path, before, after, "capture", added: [ "- something else" ]) { [ "written" ] }

      refute result.ok
      assert_equal before, OKF::Pro.read_text(path), "the guard runs before the write, not after"
      assert_match(/refused, and #{Regexp.escape(path)} is untouched/, result.messages.first)
      assert_match(/failure mode 07/, result.messages.first)
      assert_match(/a line nobody declared/, result.messages.join("\n"))
    end
  end

  test "commit writes and reports when the claim holds" do
    with_bundle do |b|
      path = File.join(b.bundle_path, "board.md")
      before = OKF::Pro.read_text(path)
      after = "#{before}- a declared line\n"

      result = OKF::Pro::Writes.commit(path, before, after, "capture", added: [ "- a declared line" ]) { [ "written" ] }

      assert result.ok
      assert_equal [ "written" ], result.messages
      assert_equal after, OKF::Pro.read_text(path)
    end
  end

  # `plan` is the same guard without the write, for the verb that changes three
  # files and must decide about all of them before it changes any.
  test "plan hands back a refusal rather than a plan when the claim fails" do
    planned, refusal = OKF::Pro::Writes.plan("/nowhere", "- a\n", "- b\n", "close", added: [ "- b" ])

    assert_nil planned
    refute refusal.ok
    assert_match(/removed that the edit did not intend: - a/, refusal.messages.join("\n"))
  end

  test "plan hands back the text to write when the claim holds" do
    planned, refusal = OKF::Pro::Writes.plan("/nowhere", "- a\n", "- a\n- b\n", "close", added: [ "- b" ])

    assert_nil refusal
    assert_equal "/nowhere", planned.path
    assert_equal "- a\n- b\n", planned.text
  end
end

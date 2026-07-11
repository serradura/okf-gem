# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Markdown::CitationsTest < OKF::TestCase
  test "section returns the text under a # Citations heading" do
    body = <<~MD
      Intro paragraph with a [claim](https://example.com/a).

      # Citations

      [1] [Source](https://example.com/a)
      [2] [Other](https://example.com/b)
    MD

    section = OKF::Markdown::Citations.section(body)

    assert_includes section, "[1] [Source](https://example.com/a)"
    assert_includes section, "[2] [Other](https://example.com/b)"
    refute_includes section, "Intro paragraph"
  end

  test "section stops at the next heading of the same or higher level" do
    body = <<~MD
      # Citations

      [1] [Source](https://example.com/a)

      # Notes

      not a citation
    MD

    section = OKF::Markdown::Citations.section(body)

    assert_includes section, "https://example.com/a"
    refute_includes section, "not a citation"
  end

  test "section matches any heading level and is case-insensitive" do
    assert OKF::Markdown::Citations.section("## citations\n\n[1] [x](https://e.com)\n")
  end

  test "section is nil when there is no Citations heading" do
    assert_nil OKF::Markdown::Citations.section("# Schema\n\njust a body\n")
  end

  test "section ignores a Citations heading inside a code fence" do
    body = <<~MD
      ```
      # Citations
      [1] [x](https://e.com)
      ```
    MD

    assert_nil OKF::Markdown::Citations.section(body)
  end

  test "targets extract the citation link targets via Links" do
    body = "# Citations\n\n[1] [Source](https://example.com/a)\n[2] [Ref](/tables/x.md)\n"

    assert_equal [ "https://example.com/a", "/tables/x.md" ], OKF::Markdown::Citations.targets(body)
  end

  test "targets is empty when there is no Citations section" do
    assert_empty OKF::Markdown::Citations.targets("just a body with a [link](/a.md)\n")
  end
end

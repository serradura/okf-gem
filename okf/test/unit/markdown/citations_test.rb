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
  # ── entries: the three §13.1 item forms a v0.1 list may use ──

  test "entries lifts labelled links with their text" do
    body = "# Citations\n\n[1] [The paper](https://ex.com/paper)\n"

    assert_equal [ { text: "The paper", target: "https://ex.com/paper" } ], OKF::Markdown::Citations.entries(body)
  end

  test "entries reads the SPEC's own bare-URL list form verbatim" do
    body = <<~MD
      # Citations
      - https://wiki.acme/finance/fpa-handbook
      - https://wiki.acme/finance/revenue-recognition
      - https://wiki.acme/finance/cost-allocation
    MD

    assert_equal [
      { text: "", target: "https://wiki.acme/finance/fpa-handbook" },
      { text: "", target: "https://wiki.acme/finance/revenue-recognition" },
      { text: "", target: "https://wiki.acme/finance/cost-allocation" }
    ], OKF::Markdown::Citations.entries(body)
  end

  test "entries reads autolink items" do
    body = "# Citations\n\n- <https://ex.com/a>\n\nprose that is not a citation stays out\n"

    assert_equal [ { text: "", target: "https://ex.com/a" } ], OKF::Markdown::Citations.entries(body)
  end

  test "entries carries reference-style citation targets with no text" do
    body = "# Citations\n\n[1][ref]\n\n[ref]: https://ex.com/r\n"

    assert_equal [ { text: "", target: "https://ex.com/r" } ], OKF::Markdown::Citations.entries(body)
  end

  test "entries mixes the three forms in document order" do
    body = "# Citations\n\n- [The paper](https://ex.com/paper)\n- https://ex.com/bare\n- <https://ex.com/auto>\n"

    assert_equal [
      { text: "The paper", target: "https://ex.com/paper" },
      { text: "", target: "https://ex.com/bare" },
      { text: "", target: "https://ex.com/auto" }
    ], OKF::Markdown::Citations.entries(body)
  end

  test "entries is empty without a Citations section" do
    assert_empty OKF::Markdown::Citations.entries("see [x](https://e.com)\n- https://ex.com/bare\n")
  end
end

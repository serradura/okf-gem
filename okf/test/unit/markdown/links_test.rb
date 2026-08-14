# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Markdown::LinksTest < OKF::TestCase
  test "extracts markdown link targets in order, ignoring images" do
    body = <<~MD
      See [Orders](tables/orders.md) and [API](/references/api.md#top).
      ![diagram](diagram.png) is an image.
    MD

    assert_equal [ "tables/orders.md", "/references/api.md#top" ], OKF::Markdown::Links.extract(body)
  end

  test "ignores links inside fenced code blocks" do
    body = <<~MD
      Real [one](a.md).
      ```
      Fake [two](b.md)
      ```
      Real [three](c.md).
    MD

    assert_equal [ "a.md", "c.md" ], OKF::Markdown::Links.extract(body)
  end

  test "ignores links inside inline code spans" do
    body = <<~MD
      Real [one](a.md), but `[fake](b.md)` is code.
      A test asserts `[Graph View](/graph-view.md)` and ``[nested `tick`](c.md)`` too.
      Real [four](d.md).
    MD

    assert_equal [ "a.md", "d.md" ], OKF::Markdown::Links.extract(body)
  end

  test "ignores reference-style links and definitions inside inline code spans" do
    body = <<~MD
      Ruby: `params[:curation_plan][:approved_link_suggestion_ids]`.

      [:approved_link_suggestion_ids]: /should-not-resolve.md
    MD

    assert_empty OKF::Markdown::Links.extract(body)
  end

  test "captures the target from a titled link" do
    assert_equal [ "x.md" ], OKF::Markdown::Links.extract(%([label](x.md "a title")))
  end

  test "resolves reference-style links against their definitions" do
    body = <<~MD
      See [the orders table][orders] and the [customers][] table.

      [orders]: /tables/orders.md
      [customers]: /tables/customers.md
    MD

    assert_equal [ "/tables/orders.md", "/tables/customers.md" ], OKF::Markdown::Links.extract(body)
  end

  test "ignores reference-style links with no matching definition" do
    assert_empty OKF::Markdown::Links.extract("A dangling [ref][missing] link.\n")
  end

  test "resolves relative and bundle-absolute targets to bundle-relative paths" do
    assert_equal "features/y.md", OKF::Markdown::Links.resolve("y.md", from: "features/x.md", bundle: "/bundle")
    assert_equal "features/sub/y.md", OKF::Markdown::Links.resolve("./sub/y.md", from: "features/x.md", bundle: "/bundle")
    assert_equal "y.md", OKF::Markdown::Links.resolve("../y.md", from: "features/x.md", bundle: "/bundle")
    assert_equal "shared/y.md", OKF::Markdown::Links.resolve("/shared/y.md", from: "features/x.md", bundle: "/bundle")
  end

  test "strips anchors before resolving" do
    assert_equal "features/y.md", OKF::Markdown::Links.resolve("y.md#section", from: "features/x.md", bundle: "/bundle")
  end

  test "returns the raw target when a relative link escapes the bundle" do
    assert_equal "../../CHANGELOG.md", OKF::Markdown::Links.resolve("../../CHANGELOG.md", from: "features/x.md", bundle: "/bundle")
  end

  test "skips targets that are not in-bundle markdown cross-links" do
    [ "https://example.com/x.md", "mailto:a@b.md", "image.png", "dir/", "" ].each do |target|
      assert_nil OKF::Markdown::Links.resolve(target, from: "features/x.md", bundle: "/bundle"), target.inspect
    end
  end
  # ── §5.1 footnotes vs reference definitions ──

  test "reference definitions exclude footnote definitions" do
    text = "[^note]: a footnote definition, not a link definition\n[real]: /a.md\n"

    assert_equal({ "real" => "/a.md" }, OKF::Markdown::Links.reference_definitions(text))
  end

  test "an unused footnote definition never yields an unused reference definition" do
    body = "A claim.[^ga4]\n\n[^ga4]: GA4 schema\n"

    assert_empty OKF::Markdown::Links.reference_definitions(body)
  end

  test "footnote references are deduplicated and never read off a definition line" do
    body = <<~MD
      A claim.[^ga4] Another claim.[^ga4] A second source.[^rev]

      [^ga4]: GA4 BigQuery Export schema
      [^orphaned]: defined but never referenced
    MD

    assert_equal %w[ga4 rev], OKF::Markdown::Links.footnote_references(body)
  end

  test "footnote references skip fenced code and inline code spans" do
    body = "Real.[^a]\n```\nFake.[^b]\n```\nAnd `code.[^c]` too.\n"

    assert_equal [ "a" ], OKF::Markdown::Links.footnote_references(body)
  end
  test "an uppercase scheme is external to links and citations alike" do
    # The scheme grammar lives in one source now; the citation regexes being
    # /i while SCHEME was not had HTTP:// counted as provenance by one module
    # and as prose by the other.
    assert_equal [ "HTTP://example.com/x" ],
      OKF::Markdown::Links.extract("see [x](HTTP://example.com/x)\n").grep(OKF::Markdown::Links::SCHEME)
    assert_equal [ { text: "", target: "HTTP://example.com/x" } ],
      OKF::Markdown::Citations.entries("# Citations\n\n- HTTP://example.com/x\n")
  end
  test "mailto is excluded case-insensitively, like every other scheme" do
    # SCHEME is /i; the mailto guard sat beside it case-sensitive, so
    # `MAILTO:user@example.md` slipped past both gates and resolved as a
    # relative path — a link outside the bundle reported as a file inside it.
    [ "mailto:user@example.md", "MAILTO:user@example.md", "MailTo:user@example.md" ].each do |raw|
      assert_nil OKF::Markdown::Links.resolve(raw, from: "features/x.md", bundle: "/bundle"), raw
      assert_nil OKF::Markdown::Links.resolve_path(raw, from: "features/x.md", bundle: "/bundle"), raw
    end
  end

  test "resolve_path accepts any extension where resolve keeps the .md gate" do
    args = { from: "metrics/revenue.md", bundle: "/bundle" }

    assert_nil OKF::Markdown::Links.resolve("attesters/revenue.py", **args)
    assert_equal "metrics/attesters/revenue.py", OKF::Markdown::Links.resolve_path("attesters/revenue.py", **args)
    assert_equal "references/rev.py", OKF::Markdown::Links.resolve_path("/references/rev.py", **args)
  end

  test "resolve_path keeps resolve's exclusions and its escape-verbatim answer" do
    args = { from: "metrics/revenue.md", bundle: "/bundle" }

    assert_nil OKF::Markdown::Links.resolve_path("", **args)
    assert_nil OKF::Markdown::Links.resolve_path("references/", **args), "a directory is not a file pointer"
    assert_nil OKF::Markdown::Links.resolve_path("https://example.com/q.sql", **args)
    assert_equal "../../outside.py", OKF::Markdown::Links.resolve_path("../../outside.py", **args),
      "an escape is returned verbatim, so a caller can name it without resolving it"
    assert_equal "references/rev.py", OKF::Markdown::Links.resolve_path("/references/rev.py#L10", **args),
      "an anchor is split off before resolution"
  end
end

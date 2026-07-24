# frozen_string_literal: true

require "test_helper"
require "okf"

class OKF::Bundle::ValidatorTest < OKF::TestCase
  setup do
    @tmpdir = Dir.mktmpdir("okf-validator-test")
  end

  teardown do
    FileUtils.rm_rf(@tmpdir)
  end

  test "accepts a minimal conformant bundle" do
    write("tables/orders.md", <<~MD)
      ---
      type: BigQuery Table
      title: Orders
      description: One row per order.
      ---

      # Orders
    MD

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?, result.errors.inspect
    assert_empty result.errors
  end

  test "accepts deeply nested concept folders" do
    write("references/vendor/contracts/api.md", <<~MD)
      ---
      type: API Reference
      ---

      Details.
    MD

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?, result.errors.inspect
  end

  test "rejects concept files without frontmatter" do
    write("tables/orders.md", "# Orders\n")

    result = OKF::Bundle::Validator.call(document)

    refute result.valid?
    assert_includes result.errors.map { |error| error[:message] }, "missing YAML frontmatter"
  end

  test "rejects missing or blank type" do
    write("tables/orders.md", <<~MD)
      ---
      title: Orders
      ---

      # Orders
    MD
    write("tables/customers.md", <<~MD)
      ---
      type: " "
      ---

      # Customers
    MD

    result = OKF::Bundle::Validator.call(document)

    refute result.valid?
    assert_equal 2, result.errors.count { |error| error[:message] == "frontmatter must include a non-empty type" }
  end

  test "tolerates unknown type and unknown frontmatter keys" do
    write("strange/thing.md", <<~MD)
      ---
      type: Local Tribal Memory
      unexpected: yes please
      ---

      Body.
    MD

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?, result.errors.inspect
  end

  test "reserved files are not concepts" do
    write("index.md", <<~MD)
      ---
      okf_version: "0.1"
      ---

      # Catalog
    MD
    write("groups/log.md", <<~MD)
      ## 2026-06-26

      Added records.
    MD

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?, result.errors.inspect
  end

  test "root index.md with extra frontmatter keys is a §9.3 error" do
    write("index.md", <<~MD)
      ---
      okf_version: "0.1"
      title: Catalog
      ---

      # Catalog
    MD

    result = OKF::Bundle::Validator.call(document)

    refute result.valid?
    assert_includes result.errors.map { |error| error[:message] }, "root index.md frontmatter may only include okf_version"
  end

  test "nested index.md with frontmatter is a §9.3 error" do
    write("groups/index.md", <<~MD)
      ---
      okf_version: "0.1"
      ---

      # Group
    MD

    result = OKF::Bundle::Validator.call(document)

    refute result.valid?
    assert_includes result.errors.map { |error| error[:message] }, "nested index.md must not include frontmatter"
  end

  test "non-ISO log.md date heading is a §9.3 error" do
    write("log.md", <<~MD)
      ## June 26, 2026

      Changed.
    MD

    result = OKF::Bundle::Validator.call(document)

    refute result.valid?
    assert_includes result.errors.map { |error| error[:message] }, "log.md date headings must use YYYY-MM-DD"
  end

  test "broken cross-links are tolerated warnings while resolved links stay silent" do
    write("a.md", <<~MD)
      ---
      type: Note
      title: A
      description: d
      ---

      See [B](b.md) and [ghost](ghost.md).
    MD
    write("b.md", <<~MD)
      ---
      type: Note
      title: B
      description: d
      ---

      hi
    MD

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?, result.errors.inspect
    messages = result.warnings.map { |warning| warning[:message] }
    assert_includes messages, "cross-link target not found: `ghost.md` (tolerated under §5.3)"
    refute_includes messages, "cross-link target not found: `b.md` (tolerated under §5.3)"
  end

  test "optional field issues are warnings" do
    write("tables/orders.md", <<~MD)
      ---
      type: BigQuery Table
      tags: sales
      timestamp: someday
      ---

      # Orders
    MD

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?, result.errors.inspect
    assert_includes result.warnings.map { |warning| warning[:message] }, "frontmatter should include title"
    assert_includes result.warnings.map { |warning| warning[:message] }, "frontmatter should include description"
    assert_includes result.warnings.map { |warning| warning[:message] }, "tags should be a list"
    assert_includes result.warnings.map { |warning| warning[:message] }, "timestamp should be ISO 8601 parseable"
  end

  test "accepts ISO 8601 timestamps — full datetime and date-only — without warning" do
    write("full.md", "---\ntype: Note\ntitle: Full\ndescription: d\ntimestamp: 2026-05-28T14:30:00Z\n---\n\nx\n")
    write("dateonly.md", "---\ntype: Note\ntitle: Date\ndescription: d\ntimestamp: 2026-05-28\n---\n\ny\n")

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?, result.errors.inspect
    refute_includes result.warnings.map { |warning| warning[:message] }, "timestamp should be ISO 8601 parseable"
  end

  private

  def document
    OKF::Bundle::Reader.read(@tmpdir)
  end

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end

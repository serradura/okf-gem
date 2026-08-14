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
    assert_includes messages, "cross-link target not found: `ghost.md` (tolerated under §6.1)"
    refute_includes messages, "cross-link target not found: `b.md` (tolerated under §6.1)"
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

  # ── the warning table is API: check ids and their sources (WI-2) ──

  test "every warning carries a distinct check id and its source, and the convention set is exact" do
    write("all-faults.md", <<~MD)
      ---
      type: Attested Computation
      tags: not-a-list
      timestamp: whenever
      generated:
        at: last tuesday
      verified:
        - nope
        - at: whenever
      sources:
        - nope
        - title: no resource
          last_modified: mid-May
          usage_count: many
          usage_window: all of June
      usage_window: all of June
      status: shipped
      stale_after: next spring
      parameters:
        - nope
        - type: integer
      executor: a path
      attester:
        language: python
      ---

      See [ghost](ghost.md).
    MD
    write("shapeless.md",
      "---\ntype: Note\ngenerated: scalar\nverified: scalar\nsources: scalar\nparameters: scalar\n" \
      "attester: scalar\nexecutor:\n  receipt: [ job_id ]\n---\n\nx\n")
    write("windowed.md", "---\ntype: Note\ntitle: W\ndescription: D\nusage_window:\n  from: early June\n  to: 2026-06-30\n---\n\nx\n")
    write("no-fields.md", "---\ntype: Note\n---\n\nx\n")
    write("index.md", "---\nokf_version: \"9.9\"\n---\n\n# Root\n\n* [All faults](all-faults.md)\n")

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?, "every one of these is a warning (§11)"
    emitted = result.warnings.map { |warning| [ warning[:check], warning[:source] ] }.uniq.sort
    expected = {
      recommended_title: :spec, recommended_description: :spec, tags_shape: :spec,
      timestamp_format: :spec, broken_link: :spec,
      generated_shape: :spec, generated_by: :spec, generated_at_format: :spec,
      verified_shape: :spec, verified_entry_shape: :spec, verified_entry_by: :convention,
      verified_entry_at_format: :spec,
      sources_shape: :spec, source_entry_shape: :spec, source_resource: :spec,
      source_usage_count: :convention, source_last_modified: :spec,
      source_usage_window_shape: :convention,
      usage_window_shape: :spec, usage_window_date: :spec,
      status_vocabulary: :spec, stale_after_format: :spec,
      runtime_required: :spec, parameters_shape: :spec, parameter_entry_shape: :spec,
      parameter_name: :convention,
      executor_shape: :spec, executor_resource: :convention, attester_shape: :spec,
      attester_resource: :convention,
      okf_version_unknown: :spec
    }

    assert_equal expected.to_a.sort, emitted, "the WI-2 warning table and the code have drifted apart"
    assert_equal OKF::Bundle::Validator::CONVENTION_CHECKS.sort,
      expected.select { |_check, source| source == :convention }.keys.sort
    assert(result.warnings.all? { |warning| warning[:check] && warning[:source] })
    assert(result.errors.all? { |error| error.keys.sort == %i[message path] },
      "errors keep their exact two-key shape — consumers read it")
  end

  test "a concept with only type is conformant, and an empty type is the error it always was" do
    write("bare.md", "---\ntype: Note\n---\n\nx\n")
    write("empty-type.md", "---\ntype: '  '\ntitle: T\ndescription: D\n---\n\nx\n")

    result = OKF::Bundle::Validator.call(document)

    refute result.valid?
    assert_equal [ "empty-type.md" ], result.errors.map { |error| error[:path] }
    refute(result.warnings.any? { |warning| warning[:path] == "bare.md" && warning[:check].to_s.start_with?("generated", "verified", "sources") })
  end

  test "unknown keys and unknown types pass silently (§4.1 MUSTs)" do
    write("odd.md", <<~MD)
      ---
      type: Completely Novel Type
      title: Odd
      description: Unknown keys must not be rejected.
      producer_extension: { anything: goes }
      another_unknown: [ 1, 2, 3 ]
      ---

      x
    MD

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?
    assert_empty result.warnings
  end

  test "a pure v0.1 concept earns zero v0.2 warnings — §13.1 consumption is silent" do
    write("legacy.md", <<~MD)
      ---
      type: Note
      title: Legacy
      description: timestamp and a Citations body, nothing else.
      timestamp: 2026-05-28
      ---

      Prose.

      # Citations

      [1] [The paper](https://ex.com/paper)
    MD

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?
    assert_empty result.warnings
  end

  test "a YAML-boolean status earns the vocabulary warning like any other stray value" do
    write("boolish.md", "---\ntype: Note\ntitle: B\ndescription: d\nstatus: no\n---\n\nx\n")

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?
    assert_includes result.warnings.map { |w| w[:message] }, "status should be one of draft, stable, deprecated"
  end

  test "a declared but blank status earns the vocabulary warning too" do
    # `status: ""` is a producer typo, not an absence: §5.4's default belongs to
    # a concept that never declared the key. Reading the blank through
    # effective_status turned it into `stable` before the vocabulary was
    # checked, so the one spelling §5.4 names nowhere passed silently — and the
    # catalog row still emitted `""` for the page to puzzle over.
    write("blank.md", "---\ntype: Note\ntitle: B\ndescription: d\nstatus: \"\"\n---\n\nx\n")
    write("spaces.md", "---\ntype: Note\ntitle: S\ndescription: d\nstatus: \"   \"\n---\n\nx\n")

    result = OKF::Bundle::Validator.call(document)

    assert result.valid?, "a stray status is a warning, never a rejection"
    assert_equal 2, result.warnings.count { |w| w[:check] == :status_vocabulary }
  end

  test "the status vocabulary check folds case the way the filters match it" do
    write("cased.md", "---\ntype: Note\ntitle: C\ndescription: d\nstatus: Stable\n---\n\nx\n")

    result = OKF::Bundle::Validator.call(document)

    refute_includes result.warnings.map { |w| w[:message] }, "status should be one of draft, stable, deprecated",
      "--status stable matches this concept; warning it as non-vocabulary is one concept, two answers"
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

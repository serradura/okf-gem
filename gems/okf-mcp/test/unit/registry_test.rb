# frozen_string_literal: true

require "test_helper"

# The registry seam alone: slug minting, ref reservation, and the resolution
# rules the integration suite exercises through tools. Hermetic like the
# integration base: a scratch $OKF_HOME, discovery off.
class RegistryTest < OKF::TestCase
  FIXTURES = File.expand_path("../integration/fixtures", __dir__)

  setup do
    @out_dir = Dir.mktmpdir("okf-mcp-unit")
    @home = Dir.mktmpdir("okf-mcp-unit-home")
    @okf_home_was = ENV.fetch("OKF_HOME", nil)
    @no_discovery_was = ENV.fetch("OKF_NO_DISCOVERY", nil)
    ENV["OKF_HOME"] = @home
    ENV["OKF_NO_DISCOVERY"] = "1"
  end

  teardown do
    @okf_home_was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = @okf_home_was
    @no_discovery_was.nil? ? ENV.delete("OKF_NO_DISCOVERY") : ENV["OKF_NO_DISCOVERY"] = @no_discovery_was
    FileUtils.rm_rf(@out_dir)
    FileUtils.rm_rf(@home)
  end

  test "a registered ref's slug is reserved before a plain dir's basename is minted" do
    plain = File.join(@out_dir, "knowledge")
    FileUtils.cp_r(File.join(FIXTURES, "knowledge"), plain)
    kernel = OKF::Registry.load
    kernel.add(File.join(FIXTURES, "knowledge")) # slug: knowledge

    # argv order puts the plain dir first; the ref still owns its slug.
    registry = OKF::MCP::Registry.from_argv([ plain, "@knowledge" ])
    assert_equal %w[knowledge-2 knowledge], registry.slugs
    assert_equal plain, registry.root!("knowledge-2")
  end

  test "the same directory listed twice serves once" do
    dir = File.join(FIXTURES, "knowledge")
    registry = OKF::MCP::Registry.from_argv([ dir, dir ])
    assert_equal [ "knowledge" ], registry.slugs
  end

  test "from_kernel with an empty registry is an error naming the registry file" do
    error = assert_raises(OKF::MCP::Error) { OKF::MCP::Registry.from_kernel }
    assert_match(/no bundles registered — run `okf registry set <dir>`/, error.message)
    assert_match(/registry\.json/, error.message)
  end

  test "from_argv with no roots is an error" do
    error = assert_raises(OKF::MCP::Error) { OKF::MCP::Registry.from_argv([]) }
    assert_match(/no bundle roots given/, error.message)
  end

  test "a vanished group member is a boot note, not a fatal" do
    goner = File.join(@out_dir, "goner")
    FileUtils.cp_r(File.join(FIXTURES, "notes"), goner)
    kernel = OKF::Registry.load
    kernel.add(File.join(FIXTURES, "knowledge"))
    kernel.add(goner)
    kernel.set_group("docs", %w[knowledge goner])
    FileUtils.rm_rf(goner)

    registry = OKF::MCP::Registry.from_argv([ "@docs" ])
    assert_equal [ "knowledge" ], registry.slugs
    assert_equal 1, registry.boot_notes.length
    assert_match(/skipped goner/, registry.boot_notes.first)
  end

  test "resolve_search dedupes by root across names and reports skips" do
    kernel = OKF::Registry.load
    kernel.add(File.join(FIXTURES, "knowledge"))
    kernel.add(File.join(FIXTURES, "notes"))
    kernel.set_group("docs", %w[knowledge notes])

    registry = OKF::MCP::Registry.from_kernel
    pairs, skipped = registry.resolve_search(%w[docs knowledge])
    assert_equal %w[knowledge notes], pairs.map(&:first)
    assert_empty skipped
  end

  test "root! refuses a group naming the one tool that takes a set" do
    kernel = OKF::Registry.load
    kernel.add(File.join(FIXTURES, "knowledge"))
    kernel.set_group("docs", %w[knowledge])

    registry = OKF::MCP::Registry.from_kernel
    error = assert_raises(OKF::MCP::Error) { registry.root!("docs") }
    assert_match(/names a group of 1 member;/, error.message)
  end

  test "the default is the first entry still on disk" do
    goner = File.join(@out_dir, "goner")
    FileUtils.cp_r(File.join(FIXTURES, "notes"), goner)
    kernel = OKF::Registry.load
    kernel.add(goner)
    kernel.add(File.join(FIXTURES, "knowledge"))
    FileUtils.rm_rf(goner)

    assert_equal "knowledge", OKF::MCP::Registry.from_kernel.default_slug
  end
end

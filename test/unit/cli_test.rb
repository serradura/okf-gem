# frozen_string_literal: true

require "test_helper"
require "okf"
require "okf/cli"
require "stringio"

class OKF::CLITest < OKF::TestCase
  # $OKF_HOME is the CLI's only lever on the registry, so it is pinned for every
  # test, not just the registry ones: a verb that reaches the registry must never
  # be one missed stub away from reading or writing the real ~/.okf.
  setup do
    @tmpdir = Dir.mktmpdir("okf-cli-test")
    @home = Dir.mktmpdir("okf-cli-home")
    @okf_home_was = ENV.fetch("OKF_HOME", nil)
    ENV["OKF_HOME"] = @home
    @out = StringIO.new
    @err = StringIO.new
  end

  teardown do
    @okf_home_was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = @okf_home_was
    FileUtils.rm_rf(@tmpdir)
    FileUtils.rm_rf(@home)
  end

  test "validate returns 0 and reports conformance for a clean bundle" do
    write("a.md", concept)

    assert_equal 0, invoke("validate", @tmpdir)
    assert_match(/conformant/, @out.string)
  end

  test "validate returns 1 for a non-conformant bundle" do
    write("a.md", "# no frontmatter\n")

    assert_equal 1, invoke("validate", @tmpdir)
    assert_match(/non-conformant/, @out.string)
  end

  test "validate returns 1 for a §9.3 structural violation" do
    write("groups/index.md", "---\nokf_version: \"0.1\"\n---\n\n# G\n") # nested index with frontmatter
    write("a.md", concept)

    assert_equal 1, invoke("validate", @tmpdir)
    assert_match(/non-conformant/, @out.string)
  end

  test "validate --json emits a machine-readable report" do
    write("a.md", concept)

    assert_equal 0, invoke("validate", @tmpdir, "--json")
    report = JSON.parse(@out.string)
    assert_equal true, report["conformant"]
    assert_equal 1, report["counts"]["concepts"]
  end

  # server now starts a blocking server; its served behavior is covered by
  # server/app_test (rack-test). Here we only exercise the synchronous paths, which
  # return before booting.
  test "server rejects an unknown layout without starting a server (exit 2)" do
    write("a.md", concept)

    assert_equal 2, invoke("server", @tmpdir, "--layout", "bogus")
    assert_match(/invalid argument: --layout bogus/, @err.string)
  end

  test "server builds the server app and hands it to the runner (no socket)" do
    write("a.md", concept)
    captured = []
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(app, host, port) { captured << [ app, host, port ] })

    assert_equal 0, cli.run([ "server", @tmpdir, "--port", "9999", "--bind", "0.0.0.0", "-t", "T" ])
    app, host, port = captured.first
    assert_kind_of Rack::Deflater, app # gzip wrap at the boot seam — guards against it silently disappearing
    assert_equal "0.0.0.0", host
    assert_equal 9999, port
    assert_match(/serving 1 concept/, @out.string)
  end

  test "render prints a static, self-contained HTML graph to stdout" do
    write("a.md", "---\ntype: Note\ntitle: A\ndescription: d\n---\n\nUNIQUEBODYMARK\n")

    assert_equal 0, invoke("render", @tmpdir)
    assert_includes @out.string, "<!doctype html"
    assert_includes @out.string, "const EMBED={"
    refute_includes @out.string, "const EMBED=null;"
    assert_includes @out.string, "UNIQUEBODYMARK", "the body is baked in — no server needed"
  end

  test "render -o writes the file and reports the concept count on stdout" do
    write("a.md", concept)
    out_file = File.join(@tmpdir, "graph.html")

    assert_equal 0, invoke("render", @tmpdir, "-o", out_file)
    assert_includes File.read(out_file), "<!doctype html"
    assert_match(/wrote 1 concept to #{Regexp.escape(out_file)}/, @out.string)
    refute_includes @out.string, "<!doctype html", "with -o, stdout carries only the confirmation"
  end

  test "render rejects an unknown layout without writing anything (exit 2)" do
    write("a.md", concept)

    assert_equal 2, invoke("render", @tmpdir, "--layout", "bogus")
    assert_match(/invalid argument: --layout bogus/, @err.string)
  end

  test "render notes skipped unparseable files on stderr and still exits 0 with valid HTML" do
    write("good.md", concept)
    write("bad.md", "no frontmatter here\n")

    assert_equal 0, invoke("render", @tmpdir)
    assert_match(/skipped 1 unusable file/, @err.string)
    assert_includes @out.string, "<!doctype html"
  end

  test "render rejects a missing directory (exit 2)" do
    assert_equal 2, invoke("render", File.join(@tmpdir, "nope"))
  end

  test "graph --minimal emits lean nodes plus type and tag indexes" do
    write("a.md", "---\ntype: Note\ntitle: A\ntags: [x]\n---\n\n[B](b.md)\n")
    write("b.md", concept("B"))

    assert_equal 0, invoke("graph", @tmpdir, "--json", "--minimal")
    data = JSON.parse(@out.string)
    assert_equal %w[id title], data["nodes"].first.keys.sort
    assert data.key?("types")
    assert data.key?("tags")
  end

  test "graph tolerates a malformed concept, skips it, and notes the skip on stderr" do
    write("good.md", concept)
    write("bad.md", "no frontmatter here\n")

    assert_equal 0, invoke("graph", @tmpdir)
    assert_match(/1 concept/, @out.string)
    assert_match(/skipped 1 unusable file/, @err.string)
  end

  test "graph --json prints nodes and edges" do
    write("a.md", "---\ntype: Note\ntitle: A\ndescription: d\n---\n\n[B](b.md)\n")
    write("b.md", concept("B"))

    assert_equal 0, invoke("graph", @tmpdir, "--json")
    data = JSON.parse(@out.string)
    assert_equal 2, data["nodes"].size
    assert_equal 1, data["edges"].size
  end

  test "loose lists degree-0 files grouped by folder, omitting linked ones" do
    write("hub.md", "---\ntype: Note\ntitle: Hub\n---\n\n[leaf](leaf.md)\n")
    write("leaf.md", concept("Leaf"))
    write("notes/floater.md", concept("Floater")) # no links in or out

    assert_equal 0, invoke("loose", @tmpdir)
    assert_match(%r{Loose files .* \(1\)}, @out.string)
    assert_match(%r{notes/\n\s+floater\.md\s+Floater}, @out.string)
    refute_match(/hub\.md|leaf\.md/, @out.string)
  end

  test "loose --json emits id, title, and dir per file" do
    write("notes/floater.md", concept("Floater"))

    assert_equal 0, invoke("loose", @tmpdir, "--json")
    data = JSON.parse(@out.string)
    assert_equal 1, data["count"]
    assert_equal({ "id" => "notes/floater", "title" => "Floater", "dir" => "notes" }, data["loose"].first)
  end

  test "unknown command returns 2 with usage on stderr" do
    assert_equal 2, invoke("frobnicate")
    assert_match(/unknown command/, @err.string)
  end

  test "a missing directory returns 2" do
    assert_equal 2, invoke("validate", File.join(@tmpdir, "nope"))
    assert_match(/not a directory/, @err.string)
  end

  test "version prints the gem version" do
    assert_equal 0, invoke("--version")
    assert_match(/\A\d+\.\d+\.\d+/, @out.string.strip)
  end

  test "catalog prints concepts by area and --json emits metadata + link degree" do
    build_sample

    assert_equal 0, invoke("catalog", @tmpdir)
    assert_match(%r{Catalog — .*\(3 concepts\)}, @out.string)
    assert_match(%r{features/ \(2\)}, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("catalog", @tmpdir, "--json")
    data = JSON.parse(@out.string)
    assert_equal 3, data["count"]
    alpha = data["concepts"].find { |concept| concept["id"] == "features/a" }
    assert_equal "features", alpha["area"]
    assert_equal 1, alpha["links_out"]
    assert_equal 1, alpha["links_in"]
  end

  test "files lists filenames by folder and --json emits paths" do
    build_sample

    assert_equal 0, invoke("files", @tmpdir)
    assert_match(%r{Files — .*\(3 files\)}, @out.string)
    assert_match(/a\.md\s+Alpha/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("files", @tmpdir, "--json")
    assert_includes JSON.parse(@out.string)["files"].map { |file| file["path"] }, "features/a.md"
  end

  test "tags lists tags by count and --json emits the index" do
    build_sample

    assert_equal 0, invoke("tags", @tmpdir)
    assert_match(%r{Tags — .*\(3 distinct\)}, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("tags", @tmpdir, "--json")
    top = JSON.parse(@out.string)["tags"].first
    assert_equal "okf", top["tag"]
    assert_equal 2, top["count"]
  end

  test "types lists types by count and --json emits the index" do
    build_sample

    assert_equal 0, invoke("types", @tmpdir)
    assert_match(%r{Types — .*\(2 distinct\)}, @out.string)
    assert_match(/Feature\s+2\s+Alpha, Beta/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("types", @tmpdir, "--json")
    top = JSON.parse(@out.string)["types"].first
    assert_equal "Feature", top["type"]
    assert_equal 2, top["count"]
  end

  test "types narrows by --tag" do
    build_sample

    assert_equal 0, invoke("types", @tmpdir, "--tag", "okf", "--json")
    data = JSON.parse(@out.string)
    assert_equal %w[Feature Mission], data["types"].map { |row| row["type"] }
    assert_equal [ "features/a" ], data["types"].first["concepts"]
  end

  test "tags narrows by --type and --area, dropping emptied tags" do
    build_sample

    assert_equal 0, invoke("tags", @tmpdir, "--type", "feature")
    assert_match(/\(2 distinct\)/, @out.string)
    refute_match(/^\s+m\s/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("tags", @tmpdir, "--area", "product", "--json")
    data = JSON.parse(@out.string)
    assert_equal %w[m okf], data["tags"].map { |row| row["tag"] }.sort
    assert_equal [ "product/mission" ], data["tags"].first["concepts"]
  end

  test "catalog narrows by --type/--tag and reports the narrowed count" do
    build_sample

    assert_equal 0, invoke("catalog", @tmpdir, "--type", "feature", "--tag", "okf")
    assert_match(/\(1 of 3 concepts\)/, @out.string)
    assert_match(/Alpha/, @out.string)
    refute_match(/Mission|Beta/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("catalog", @tmpdir, "--area", "product", "--json")
    data = JSON.parse(@out.string)
    assert_equal 1, data["count"]
    assert_equal "product/mission", data["concepts"].first["id"]
  end

  test "files narrows by --tag" do
    build_sample

    assert_equal 0, invoke("files", @tmpdir, "--tag", "x")
    assert_match(/\(2 of 3 files\)/, @out.string)
    refute_match(/mission\.md/, @out.string)
  end

  test "tags --by area groups tags with within-group counts" do
    build_sample

    assert_equal 0, invoke("tags", @tmpdir, "--by", "area")
    assert_match(/3 distinct, by area/, @out.string)
    assert_match(%r{features/ \(2 tags\)}, @out.string)
    assert_match(/x\s+2\s+Alpha, Beta/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("tags", @tmpdir, "--by", "area", "--json")
    data = JSON.parse(@out.string)
    assert_equal "area", data["by"]
    features = data["groups"].find { |group| group["area"] == "features" }
    assert_equal 2, features["count"]
    top = features["tags"].first
    assert_equal [ "x", 2 ], [ top["tag"], top["count"] ]
    assert_equal %w[features/a features/b], top["concepts"].sort
  end

  test "tags --by type composes with filters and rejects a bad dimension" do
    build_sample

    assert_equal 0, invoke("tags", @tmpdir, "--by", "type", "--area", "features", "--json")
    data = JSON.parse(@out.string)
    assert_equal [ "Feature" ], data["groups"].map { |group| group["type"] }

    assert_equal 2, invoke("tags", @tmpdir, "--by", "folder")
    assert_match(/invalid argument: --by folder/, @err.string)
  end

  test "a filter matching nothing yields an empty view, not an error" do
    build_sample

    assert_equal 0, invoke("tags", @tmpdir, "--type", "nope")
    assert_match(/\(0 distinct\)/, @out.string)
  end

  test "a concept at the bundle root lives in the (root) area" do
    write("loose-note.md", concept("Root note"))
    write("features/a.md", concept("Alpha"))

    assert_equal 0, invoke("stats", @tmpdir, "--json")
    assert_equal({ "features" => 1, "(root)" => 1 }, JSON.parse(@out.string)["by_area"])

    @out = StringIO.new
    assert_equal 0, invoke("catalog", @tmpdir, "--area", "root")
    assert_match(/\(1 of 2 concepts\)/, @out.string)
    assert_match(/\(root\) \(1\)/, @out.string)
    assert_match(/Root note/, @out.string)
  end

  test "stats reports rollups and --json emits by_type / by_area" do
    build_sample

    assert_equal 0, invoke("stats", @tmpdir)
    assert_match(/concepts\s+3/, @out.string)
    assert_match(/cross-links\s+2/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("stats", @tmpdir, "--json")
    data = JSON.parse(@out.string)
    assert_equal 2, data["areas"]
    assert_equal 2, data["cross_links"]
    assert_equal({ "Feature" => 2, "Mission" => 1 }, data["by_type"])
    assert_equal 2, data["by_area"]["features"]
  end

  test "index maps directories with their authored index body and rollups" do
    write("index.md", "---\nokf_version: \"0.1\"\n---\n\n# Root\n")
    write("product/index.md", "# Product\n\n* [Mission](mission.md)\n")
    write("product/mission.md", concept("Mission"))

    assert_equal 0, invoke("index", @tmpdir)
    assert_match(/Index map/, @out.string)
    assert_match(%r{product/  ·  1 concept}, @out.string)
    assert_match(/# Product/, @out.string)
  end

  test "index --json emits per-directory entries with listing and rollups" do
    write("product/index.md", "# Product\n")
    write("product/mission.md", concept("Mission"))
    write("product/vision.md", "---\ntype: Note\ntitle: Vision\ndescription: d\n---\n\nhi\n")

    assert_equal 0, invoke("index", @tmpdir, "--json")
    data = JSON.parse(@out.string)
    prod = data["directories"].find { |entry| entry["dir"] == "product" }
    assert_equal 2, prod["count"]
    assert_equal true, prod["present"]
    assert_equal({ "Note" => 2 }, prod["types"])
    assert_equal %w[product/mission product/vision], prod["listing"].map { |item| item["id"] }
  end

  test "index --area narrows to the named directories; repeatable and root-aware" do
    write("index.md", "---\nokf_version: \"0.1\"\n---\n\n# Root\n")
    write("a/x.md", concept("X"))
    write("b/y.md", concept("Y"))

    assert_equal 0, invoke("index", @tmpdir, "--area", "a")
    assert_match(/\(1 directory\)/, @out.string)
    assert_match(%r{\n  a/}, @out.string)
    refute_match(%r{\n  b/}, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("index", @tmpdir, "--area", "root", "--area", "b")
    assert_match(/\(2 directories\)/, @out.string)
    assert_match(/\n  \(root\)/, @out.string)
    assert_match(%r{\n  b/}, @out.string)
  end

  test "index --no-body omits an authored body but keeps a synthesized listing" do
    write("index.md", "---\nokf_version: \"0.1\"\n---\n\n# UNIQUEBODYMARKER\n")
    write("a/x.md", concept("Xtitle")) # no index.md in a/ -> synthesized

    assert_equal 0, invoke("index", @tmpdir)
    assert_match(/UNIQUEBODYMARKER/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("index", @tmpdir, "--no-body")
    refute_match(/UNIQUEBODYMARKER/, @out.string)
    assert_match(/no index\.md/, @out.string)
    assert_match(/• Xtitle/, @out.string)
  end

  test "index notes skipped unparseable files on stderr and still exits 0" do
    write("good.md", concept)
    write("bad.md", "no frontmatter here\n")

    assert_equal 0, invoke("index", @tmpdir)
    assert_match(/skipped 1 unusable file/, @err.string)
  end

  test "index rejects a missing directory (exit 2)" do
    assert_equal 2, invoke("index", File.join(@tmpdir, "nope"))
  end

  test "--json emits compact single-line JSON by default" do
    build_sample

    assert_equal 0, invoke("catalog", @tmpdir, "--json")
    out = @out.string
    assert JSON.parse(out), "compact output is valid JSON"
    refute_match(/\n/, out.strip, "compact JSON is a single line")
  end

  test "--pretty indents the JSON and implies --json" do
    build_sample

    assert_equal 0, invoke("catalog", @tmpdir, "--pretty") # no --json
    out = @out.string
    assert JSON.parse(out), "pretty output is still valid JSON"
    assert_match(/\n {2}/, out, "pretty JSON is indented")
  end

  test "compact JSON is the shared default across emitting verbs (validate too)" do
    write("a.md", concept)

    assert_equal 0, invoke("validate", @tmpdir, "--json")
    refute_match(/\n/, @out.string.strip)
  end

  test "--fields keeps only the named properties and implies --json" do
    write("product/index.md", "# P\n")
    write("product/mission.md", concept("Mission"))

    assert_equal 0, invoke("index", @tmpdir, "--fields", "dir,count") # no --json
    entry = JSON.parse(@out.string)["directories"].find { |e| e["dir"] == "product" }
    assert_equal %w[count dir], entry.keys.sort
    refute entry.key?("body"), "dropped properties are absent"
  end

  test "--except drops the named properties" do
    write("product/mission.md", concept("Mission"))

    assert_equal 0, invoke("index", @tmpdir, "--except", "body,listing", "--json")
    entry = JSON.parse(@out.string)["directories"].first
    refute entry.key?("body")
    refute entry.key?("listing")
    assert entry.key?("count"), "unnamed properties are kept"
  end

  test "projection generalizes to catalog" do
    build_sample

    assert_equal 0, invoke("catalog", @tmpdir, "--fields", "id,type")
    assert_equal %w[id type], JSON.parse(@out.string)["concepts"].first.keys.sort
  end

  test "index --no-body drops the body property from JSON too" do
    write("index.md", "---\nokf_version: \"0.1\"\n---\n\n# Root\n")
    write("a.md", concept)

    assert_equal 0, invoke("index", @tmpdir, "--json", "--no-body")
    assert JSON.parse(@out.string)["directories"].none? { |e| e.key?("body") }, "no directory keeps body"
  end

  test "an unknown projection field is a usage error listing the valid ones" do
    write("a.md", concept)

    assert_equal 2, invoke("catalog", @tmpdir, "--fields", "bogus")
    assert_match(/unknown field/, @err.string)
    assert_match(/available:.*\bid\b/, @err.string)
  end

  test "--fields and --except together is a usage error" do
    write("a.md", concept)

    assert_equal 2, invoke("catalog", @tmpdir, "--fields", "id", "--except", "type")
    assert_match(/mutually exclusive/, @err.string)
  end

  test "search prints ranked matches with where they hit" do
    build_sample

    assert_equal 0, invoke("search", @tmpdir, "alpha")
    assert_match(/Search — .* · alpha \(2 of 3 concepts\)/, @out.string)
    assert_match(%r{features/a\s+Alpha\s+·\s+Feature\s+·\s+title}, @out.string)
    assert_operator @out.string.index("features/a"), :<, @out.string.index("product/mission"),
      "a title hit ranks above a body hit"
  end

  test "search with no matches stays exit 0 (advisory read)" do
    write("a.md", concept)

    assert_equal 0, invoke("search", @tmpdir, "absent-term")
    assert_match(/no matches/, @out.string)
  end

  test "search --json carries the query and the ranked rows" do
    build_sample

    assert_equal 0, invoke("search", @tmpdir, "alpha", "--json")
    data = JSON.parse(@out.string)
    assert_equal [ "alpha" ], data["query"]
    assert_equal 2, data["count"]
    assert_equal "features/a", data["matches"].first["id"]
    assert_equal %w[area dir id matched score snippet tags title type], data["matches"].first.keys.sort
  end

  test "search terms are ANDed across fields" do
    build_sample

    assert_equal 0, invoke("search", @tmpdir, "alpha", "beta", "--json")
    assert_equal [ "features/a" ], JSON.parse(@out.string)["matches"].map { |row| row["id"] }
  end

  test "search composes with the shared filters" do
    build_sample

    assert_equal 0, invoke("search", @tmpdir, "okf", "--area", "product", "--json")
    assert_equal [ "product/mission" ], JSON.parse(@out.string)["matches"].map { |row| row["id"] }
  end

  test "search --in restricts the searched fields" do
    build_sample

    assert_equal 0, invoke("search", @tmpdir, "alpha", "--in", "body", "--json")
    assert_equal [ "product/mission" ], JSON.parse(@out.string)["matches"].map { |row| row["id"] }
  end

  test "search --in rejects an unknown field, listing the searchable ones" do
    write("a.md", concept)

    assert_equal 2, invoke("search", @tmpdir, "x", "--in", "bogus")
    assert_match(/unknown field\(s\): bogus/, @err.string)
    assert_match(/searchable:.*\bbody\b/, @err.string)
  end

  test "search without a term is a usage error" do
    write("a.md", concept)

    assert_equal 2, invoke("search", @tmpdir)
    assert_match(/Usage: okf search/, @err.string)
  end

  test "search --regexp matches Ruby patterns" do
    build_sample

    assert_equal 0, invoke("search", @tmpdir, "al.ha|beta", "--regexp", "--json")
    ids = JSON.parse(@out.string)["matches"].map { |row| row["id"] }
    assert_includes ids, "features/a"
    assert_includes ids, "features/b"
  end

  test "search --regexp rejects an invalid pattern as a usage error" do
    write("a.md", concept)

    assert_equal 2, invoke("search", @tmpdir, "[unclosed", "--regexp")
    assert_match(/invalid pattern/, @err.string)
  end

  test "projection generalizes to search" do
    build_sample

    assert_equal 0, invoke("search", @tmpdir, "alpha", "--fields", "id,score")
    assert_equal %w[id score], JSON.parse(@out.string)["matches"].first.keys.sort
  end

  # ── registry verbs + multi-bundle server ──

  test "registry set adds a bundle to the registry and reports its slug" do
    write("one/a.md", concept)

    assert_equal 0, invoke("registry", "set", File.join(@tmpdir, "one"))
    assert_match(/registered one/, @out.string)
    assert_equal [ "one" ], OKF::Registry.load(home: @home).slugs
  end

  test "registry set --as sets the slug; a missing dir is a usage error (exit 2)" do
    write("one/a.md", concept)

    assert_equal 0, invoke("registry", "set", File.join(@tmpdir, "one"), "--as", "uno")
    assert_equal [ "uno" ], OKF::Registry.load(home: @home).slugs

    assert_equal 2, invoke("registry", "set", File.join(@tmpdir, "ghost"))
  end

  test "registry lists registered bundles, and --json emits them with mount paths" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))

    @out = StringIO.new
    assert_equal 0, invoke("registry")
    assert_match(/^\* one\s/, @out.string, "the sole bundle is the default, starred")

    @out = StringIO.new
    assert_equal 0, invoke("registry", "--json")
    payload = JSON.parse(@out.string)
    assert_equal File.join(@home, "registry.json"), payload["registry"], "the envelope names the file it read"
    assert_equal 1, payload["count"]
    rows = payload["bundles"]
    assert_equal [ "one" ], rows.map { |row| row["slug"] }
    assert_equal "/b/one/", rows.first["mount"]
    assert_equal File.join(@tmpdir, "one"), rows.first["dir"]
    assert_equal true, rows.first["default"]
    assert_equal false, rows.first["missing"]
  end

  test "registry list is the explicit spelling of the bare listing" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))

    @out = StringIO.new
    assert_equal 0, invoke("registry", "list")
    assert_match(/^\* one\s/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("registry", "list", "--json")
    assert_equal [ "one" ], JSON.parse(@out.string)["bundles"].map { |row| row["slug"] }
  end

  test "registry list --json keeps the object envelope every other --json view uses" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    @out = StringIO.new

    assert_equal 0, invoke("registry", "list", "--json")
    payload = JSON.parse(@out.string)
    assert_kind_of Hash, payload, "a bare array would break the CLI's one JSON shape"
    assert_equal %w[bundles count groups registry], payload.keys.sort
  end

  test "--pretty does not leak into a later run on a reused CLI instance" do
    write("a.md", concept)
    cli = OKF::CLI.new(out: @out, err: @err)

    assert_equal 0, cli.run([ "catalog", @tmpdir, "--json", "--pretty" ])
    assert_match(/\n\s+"/, @out.string.strip, "the pretty run indents")

    cli.instance_variable_set(:@out, @out = StringIO.new)
    assert_equal 0, cli.run([ "catalog", @tmpdir, "--json" ])
    refute_match(/\n\s+"/, @out.string.strip, "a later --json run is compact again")
  end

  test "registry set keys on the path: a known dir is updated in place, not duplicated" do
    write("one/a.md", concept)
    dir = File.join(@tmpdir, "one")
    invoke("registry", "set", dir)

    # Re-setting the same path renames it rather than adding a second entry —
    # this is what lets `set` stand in for a rename without a slug positional.
    @out = StringIO.new
    assert_equal 0, invoke("registry", "set", dir, "--as", "uno")
    reg = OKF::Registry.load(home: @home)
    assert_equal [ "uno" ], reg.slugs
    assert_equal 1, reg.size
    assert_match(/^updated uno/, @out.string, "an update must not report itself as a fresh registration")
  end

  test "an unknown registry subcommand is a usage error, not a silent listing" do
    assert_equal 2, invoke("registry", "remove", "docs")
    assert_match(/unknown registry subcommand 'remove'/, @err.string)
    assert_match(/expected: set, del, list, default, rename/, @err.string)
  end

  test "extra positionals are rejected, not silently dropped" do
    write("one/a.md", concept)
    write("two/a.md", concept)

    assert_equal 2, invoke("registry", "set", File.join(@tmpdir, "one"), File.join(@tmpdir, "two"))
    assert_match(/unexpected argument/, @err.string)
    assert_equal 0, OKF::Registry.load(home: @home).size, "nothing was half-registered"
  end

  test "a corrupt registry file is the same clean usage error on every verb" do
    FileUtils.mkdir_p(@home)
    File.write(File.join(@home, "registry.json"), "{ not json")

    [ %w[registry], %w[registry del x], %w[registry default x], %w[registry rename a b], %w[server] ].each do |argv|
      @err = StringIO.new
      assert_equal 2, invoke(*argv), "#{argv.join(" ")} exit code"
      assert_match(/error: malformed registry/, @err.string, argv.join(" "))
    end
  end

  test "a registered directory that vanished is flagged in the list and skipped by the server" do
    write("one/a.md", concept)
    write("two/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"), "--default")
    invoke("registry", "set", File.join(@tmpdir, "two"))
    FileUtils.rm_rf(File.join(@tmpdir, "one"))

    @out = StringIO.new
    invoke("registry")
    assert_match(/one.*\(missing\)/, @out.string)

    captured = []
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(app, _host, _port) { captured << app })
    assert_equal 0, cli.run([ "server" ])
    assert_match(/note: skipping one/, @err.string)
    status, headers, = captured.first.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/", "QUERY_STRING" => "", "rack.input" => StringIO.new(""))
    assert_equal 302, status
    assert_equal "/b/two/", headers["location"], "the vanished default falls back to a live bundle"
  end

  test "registry default switches the starred bundle; an unknown slug is a usage error" do
    write("one/a.md", concept)
    write("two/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    invoke("registry", "set", File.join(@tmpdir, "two"))

    assert_equal 0, invoke("registry", "default", "two")
    assert_match(/default bundle → two/, @out.string)

    @out = StringIO.new
    invoke("registry")
    assert_match(/^\* two\s/, @out.string)
    assert_match(/^ {2}one\s/, @out.string)

    assert_equal 2, invoke("registry", "default", "ghost")
    assert_match(/no such bundle: ghost/, @err.string)
  end

  test "registry set --default takes the default from the incumbent" do
    write("one/a.md", concept)
    write("two/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))

    assert_equal 0, invoke("registry", "set", File.join(@tmpdir, "two"), "--default")
    assert_equal "two", OKF::Registry.load(home: @home).default.slug
  end

  test "registry rename changes the slug; unknown and missing args are usage errors" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))

    assert_equal 0, invoke("registry", "rename", "one", "uno")
    assert_match(/renamed one → uno/, @out.string)
    assert_equal [ "uno" ], OKF::Registry.load(home: @home).slugs

    assert_equal 2, invoke("registry", "rename", "ghost", "x")
    assert_equal 2, invoke("registry", "rename", "uno")
  end

  test "a bare server honours the registry's chosen default at /" do
    write("one/a.md", concept)
    write("two/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    invoke("registry", "set", File.join(@tmpdir, "two"))
    invoke("registry", "default", "two")
    captured = []
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(app, _host, _port) { captured << app })

    assert_equal 0, cli.run([ "server" ])
    status, headers, = captured.first.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/", "QUERY_STRING" => "", "rack.input" => StringIO.new(""))
    assert_equal 302, status
    assert_equal "/b/two/", headers["location"]
  end

  test "registry with nothing registered says so" do
    assert_equal 0, invoke("registry")
    assert_match(/no bundles registered/, @out.string)
  end

  test "registry del removes a bundle; an unknown slug is a usage error (exit 2)" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))

    assert_equal 0, invoke("registry", "del", "one")
    assert_empty OKF::Registry.load(home: @home).slugs

    assert_equal 2, invoke("registry", "del", "ghost")
    assert_match(/no such bundle: ghost/, @err.string)
  end

  test "server with two dirs hands a hub (not a single App) to the runner" do
    write("one/a.md", concept)
    write("two/a.md", concept)
    captured = []
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(app, host, port) { captured << [ app, host, port ] })

    assert_equal 0, cli.run([ "server", File.join(@tmpdir, "one"), File.join(@tmpdir, "two") ])
    assert_kind_of OKF::Server::Hub, booted_app(captured.first.first)
    assert_match(/serving 2 bundles/, @out.string)
    assert_match(%r{^ {2}\* /b/one/}, @out.string, "the mount table marks the default")
    assert_match(%r{^ {4}/b/two/}, @out.string)
  end

  test "server notes flags that will have no effect in the chosen mode" do
    write("one/a.md", concept)
    write("two/a.md", concept)
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(*) {})

    cli.run([ "server", File.join(@tmpdir, "one"), File.join(@tmpdir, "two"), "-t", "T" ])
    assert_match(/note: --title\/--link apply to a single-bundle server/, @err.string)
  end

  test "the same directory passed twice mounts once" do
    write("one/a.md", concept)
    captured = []
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(app, *) { captured << app })

    assert_equal 0, cli.run([ "server", File.join(@tmpdir, "one"), File.join(@tmpdir, "one") ])
    assert_match(/serving 1 bundle/, @out.string)
  end

  test "registry set reports the concept count so a typo'd path is caught at once" do
    write("one/a.md", concept)
    FileUtils.mkdir_p(File.join(@tmpdir, "empty"))

    invoke("registry", "set", File.join(@tmpdir, "one"))
    assert_match(/\(1 concept\)/, @out.string)

    @out = StringIO.new
    invoke("registry", "set", File.join(@tmpdir, "empty"))
    assert_match(/\(0 concepts\)/, @out.string)
  end

  # -- @refs: any <bundle-dir> positional resolves a registered bundle by slug.
  # Refs read the registry through $OKF_HOME, pinned at @home by setup.

  test "@slug points any verb at a registered bundle" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))

    assert_equal 0, invoke("lint", "@one")
    assert_match(/concepts: 1/, @out.string)
  end

  test "bare @ resolves to the registry default" do
    write("one/a.md", concept)
    write("two/a.md", concept)
    write("two/b.md", concept("B"))
    invoke("registry", "set", File.join(@tmpdir, "one"))
    invoke("registry", "set", File.join(@tmpdir, "two"), "--default")

    assert_equal 0, invoke("stats", "@")
    assert_match(/concepts\s+2/, @out.string, "@ picks the chosen default, not the first entry")
  end

  test "an unknown @ref is a usage error that points at the registry" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))

    assert_equal 2, invoke("lint", "@ghost")
    assert_match(%r{not a registered bundle: @ghost in \S*registry\.json \(okf registry list\)}, @err.string,
      "the error names the registry file consulted, so a $OKF_HOME mismatch self-diagnoses")
  end

  test "a bundle named by @ref is identified as one in human output and JSON" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"), "--as", "handbook")
    dir = File.join(@tmpdir, "one")

    @out = StringIO.new
    assert_equal 0, invoke("lint", "@handbook")
    assert_match(/OKF lint — @handbook \(#{Regexp.escape(dir)}\)/, @out.string,
      "the header answers in the identity the caller used")

    @out = StringIO.new
    assert_equal 0, invoke("catalog", "@handbook", "--json")
    payload = JSON.parse(@out.string)
    assert_equal "handbook", payload["slug"], "slug always means a registry slug"
    assert_equal dir, payload["bundle"], "bundle always means the directory"
  end

  test "a bundle named by path carries no slug — a name it was never given is not invented" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"), "--as", "handbook")
    @out = StringIO.new

    # Registered, but named by path: resolving the slug would cost a registry
    # read on every plain-dir run, and the caller did not ask by that name.
    assert_equal 0, invoke("catalog", File.join(@tmpdir, "one"), "--json")
    payload = JSON.parse(@out.string)
    refute payload.key?("slug")
    assert_equal File.join(@tmpdir, "one"), payload["bundle"]
  end

  test "an @ref is slugified like registration was — @One finds the bundle from dir One" do
    write("One/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "One"))

    assert_equal 0, invoke("lint", "@One")
  end

  test "an @ref against an empty registry hints at registry set" do
    assert_equal 2, invoke("validate", "@")
    assert_match(/okf registry set/, @err.string)
  end

  test "an @ref whose registered directory is gone is a usage error, not a skip" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    FileUtils.rm_rf(File.join(@tmpdir, "one"))

    assert_equal 2, invoke("lint", "@one")
    assert_match(/@one points to .*, which is not a directory \(okf registry del one/, @err.string,
      "the error names the next move")
  end

  test "ref slugs do not leak between runs on a reused CLI instance" do
    write("one/a.md", concept)
    write("two/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"), "--as", "uno")
    captured = []
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(app, *) { captured << app })

    assert_equal 0, cli.run([ "lint", "@uno" ])
    assert_equal 0, cli.run([ "server", File.join(@tmpdir, "one"), File.join(@tmpdir, "two") ])
    assert_match(%r{/b/one/}, @out.string)
    refute_match(%r{/b/uno/}, @out.string, "a plain-dir server must not inherit an earlier run's ref slug")
  end

  test "a registered slug owns its mount — an unregistered dir of the same name takes the suffix" do
    write("two/a.md", concept)
    write("other/two/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "two"))
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(*) {})

    # The plain dir leads, so argv order would hand it /b/two/ — but the ref
    # reserved that slug, and a bookmark to /b/two/ must keep meaning @two.
    assert_equal 0, cli.run([ "server", File.join(@tmpdir, "other", "two"), "@two" ])
    refute_match(%r{/b/two/\s+other/two}, @out.string, "the unregistered dir must not take the registered slug")
    assert_match(%r{/b/two-2/\s+other/two}, @out.string, "it takes the suffix instead")
  end

  test "a punctuation-only @ref is unknown, not the bundle slugged 'bundle'" do
    write("gamma/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "gamma"), "--as", "bundle")

    assert_equal 2, invoke("search", "@***", "hi")
    assert_match(/not a registered bundle: @\*\*\*/, @err.string)
  end

  test "a malformed registry is a usage error on an @ref verb, not a backtrace" do
    File.write(File.join(@home, "registry.json"), "not json at all")

    assert_equal 2, invoke("validate", "@docs")
    assert_match(/malformed registry at .*registry\.json/, @err.string)
    refute_match(/note: searching for a literal/, @err.string)
  end

  test "a structurally incomplete registry entry is a usage error, not a TypeError" do
    File.write(File.join(@home, "registry.json"), '{"bundles":[{"slug":"a","title":"A"}]}')

    assert_equal 2, invoke("registry", "list")
    assert_match(/every entry needs a "slug" and a "path"/, @err.string)
  end

  test "a registry subcommand behind a flag is a usage error, never a silent no-op" do
    write("one/a.md", concept)

    assert_equal 2, invoke("registry", "--json", "set", File.join(@tmpdir, "one"))
    assert_match(/put the subcommand first: okf registry set/, @err.string)
    refute File.exist?(File.join(@home, "registry.json")), "nothing was written"
  end

  test "search points @all and refs at the registry $OKF_HOME names" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    @out = StringIO.new

    assert_equal 0, invoke("search", "@all", "hi")
    assert_match(/@one/, @out.string)

    @out = StringIO.new
    assert_equal 0, invoke("search", "@one", "hi")
    assert_match(/@one/, @out.string)
  end

  test "registry set reads and writes one registry — the one $OKF_HOME names" do
    write("a-docs/x.md", concept("A"))
    write("b-docs/x.md", concept("B"))
    other = Dir.mktmpdir("okf-cli-home-b")

    begin
      invoke("registry", "set", File.join(@tmpdir, "a-docs"), "--as", "docs")
      with_home(other) do
        invoke("registry", "set", File.join(@tmpdir, "b-docs"), "--as", "docs")

        # Both registries know a "docs"; @docs must mean the one being written,
        # never the other, or the write plants a foreign path.
        assert_equal 0, invoke("registry", "set", "@docs", "--as", "manual")
      end
      entries = OKF::Registry.load(home: other).listing
      assert_equal [ "manual" ], entries.map { |row| row[:slug] }, "the rename lands on that registry's own bundle"
      assert_equal File.join(@tmpdir, "b-docs"), entries.first[:dir], "and never adopts the other registry's path"
      assert_equal [ "docs" ], OKF::Registry.load(home: @home).slugs, "the registry it was pointed away from is untouched"
    ensure
      FileUtils.rm_rf(other)
    end
  end

  test "registry del takes an @ref, and still removes an entry whose directory is gone" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    FileUtils.rm_rf(File.join(@tmpdir, "one")) # the case you most want to delete
    @out = StringIO.new

    assert_equal 0, invoke("registry", "del", "@one")
    assert_match(/removed one/, @out.string)
    assert_empty OKF::Registry.load(home: @home).slugs
  end

  test "registry del @ resolves the default; with nothing registered it is a usage error" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    @out = StringIO.new

    assert_equal 0, invoke("registry", "del", "@")
    assert_match(/removed one/, @out.string)

    assert_equal 2, invoke("registry", "del", "@")
    assert_match(/no bundle is registered, so `@` names nothing/, @err.string)
  end

  test "an unexpandable slug is a usage error (exit 2), never a backtrace" do
    # exit 1 means "failing bundle"; a bad argument must not borrow that code.
    # `del` only reaches the path comparison once an entry exists to compare
    # against; on an empty registry it answers "no such bundle" without ever
    # expanding.
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    @err = StringIO.new
    assert_equal 2, invoke("registry", "del", "~nosuchuser")
    assert_match(/cannot expand ~nosuchuser/, @err.string)
  end

  test "an unexpandable $OKF_HOME is a usage error on a verb that takes an @ref" do
    with_home("~nosuchuser") do
      assert_equal 2, invoke("lint", "@docs")
      assert_match(/cannot expand ~nosuchuser/, @err.string)
    end
  end

  test "registry list rejects a stray positional instead of answering the unfiltered list" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    @out = StringIO.new

    assert_equal 2, invoke("registry", "list", "one")
    assert_match(/unexpected argument 'one'/, @err.string)
    assert_equal "", @out.string, "no list is printed when the ask was not understood"
  end

  test "after @all every positional is a term, even one that names a directory — silently" do
    write("one/a.md", concept)
    write("lib/a.md", concept("Lib"))
    invoke("registry", "set", File.join(@tmpdir, "one"))

    # @all took slot 1, so nothing downstream can be read as a bundle. The old
    # --all needed a note here because the flag flipped what slot 1 meant; a ref
    # cannot flip it, so there is nothing left to warn about.
    assert_equal 0, invoke("search", "@all", File.join(@tmpdir, "lib"), "hi")
    refute_match(/searches as a literal term/, @err.string)
  end

  test "the same @all search succeeds regardless of the directory it runs from" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    FileUtils.mkdir_p(File.join(@tmpdir, "hi")) # the term now names a cwd entry

    Dir.chdir(@tmpdir) do
      assert_equal 0, invoke("search", "@all", "hi"), "a cwd directory named like the term must not fail the search"
    end
  end

  test "server with @refs mounts each bundle under its registered slug" do
    write("one/a.md", concept)
    write("two/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"), "--as", "uno")
    invoke("registry", "set", File.join(@tmpdir, "two"))
    captured = []
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(app, *) { captured << app })

    assert_equal 0, cli.run([ "server", "@uno", "@two" ])
    assert_kind_of OKF::Server::Hub, booted_app(captured.first)
    assert_match(%r{/b/uno/}, @out.string, "the mount carries the registry slug, not the dir basename")
  end

  # -- registry-mode search: leading @refs, @all among them, span several bundles.

  test "search with several @refs merges the rankings and labels each row" do
    write("one/a.md", concept("Alpha"))
    write("two/a.md", concept("Beta"))
    invoke("registry", "set", File.join(@tmpdir, "one"))
    invoke("registry", "set", File.join(@tmpdir, "two"))

    assert_equal 0, invoke("search", "@one", "@two", "hi")
    assert_match(/Search — @one @two · hi/, @out.string)
    assert_match(/^ {2}@one +a +Alpha/, @out.string)
    assert_match(/^ {2}@two +a +Beta/, @out.string)
  end

  test "registry-mode search --json carries the bundles and a bundle per match" do
    write("one/a.md", concept("Alpha"))
    write("two/a.md", concept("Beta"))
    invoke("registry", "set", File.join(@tmpdir, "one"))
    invoke("registry", "set", File.join(@tmpdir, "two"))
    @out = StringIO.new

    # Refs typed in one order, equal scores: the payload keeps the typed
    # order, the merged ranking breaks the tie by slug — deterministically.
    assert_equal 0, invoke("search", "@two", "@one", "hi", "--json")
    payload = JSON.parse(@out.string)
    assert_equal %w[two one], payload["bundles"].map { |bundle| bundle["slug"] }
    assert_equal [ File.join(@tmpdir, "two"), File.join(@tmpdir, "one") ], payload["bundles"].map { |bundle| bundle["dir"] },
      "the head maps each slug to its dir, so a row resolves to a file without a second lookup"
    assert_equal %w[one two], payload["matches"].map { |row| row["slug"] }

    @out = StringIO.new
    assert_equal 0, invoke("search", "@one", "hi", "--json")
    single = JSON.parse(@out.string)
    assert_equal [ "one" ], single["bundles"].map { |bundle| bundle["slug"] }, "one ref still answers in registry shape"
  end

  test "search @all covers every registered bundle and skips a gone one with a note" do
    write("one/a.md", concept("Alpha"))
    write("two/a.md", concept("Beta"))
    write("three/a.md", concept("Gamma"))
    %w[one two three].each { |dir| invoke("registry", "set", File.join(@tmpdir, dir)) }
    FileUtils.rm_rf(File.join(@tmpdir, "three"))

    assert_equal 0, invoke("search", "@all", "hi")
    assert_match(/Alpha/, @out.string)
    assert_match(/Beta/, @out.string)
    refute_match(/Gamma/, @out.string)
    assert_match(/skipping three/, @err.string)
  end

  test "search dedupes refs by resolved bundle — @ plus its own slug is one target" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    @out = StringIO.new

    assert_equal 0, invoke("search", "@", "@one", "hi", "--json")
    payload = JSON.parse(@out.string)
    assert_equal [ "one" ], payload["bundles"].map { |bundle| bundle["slug"] }
    assert_equal 1, payload["count"]
  end

  test "a non-leading @arg is a literal term, and a note says so" do
    write("one/a.md", concept)

    assert_equal 0, invoke("search", File.join(@tmpdir, "one"), "@ghost", "hi")
    assert_match(/'@ghost' searches as a literal term — an @slug or @all must lead/, @err.string)
  end

  test "an eaten literal @-term gets an escape-hatch hint" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))

    assert_equal 2, invoke("search", "@one", "@babel/core")
    assert_match(/put a non-@ term first, or use -e/, @err.string)
  end

  test "search @all with an empty registry is a usage error" do
    assert_equal 2, invoke("search", "@all", "hi")
    assert_match(/no bundles registered/, @err.string)
  end

  test "search @all dedupes against a named ref; a ref with no terms is the banner" do
    write("one/a.md", concept)
    invoke("registry", "set", File.join(@tmpdir, "one"))
    @out = StringIO.new

    assert_equal 0, invoke("search", "@all", "@one", "hi", "--json"), "all ⊇ one — a correct ask, not an error"
    assert_equal [ "one" ], JSON.parse(@out.string)["bundles"].map { |bundle| bundle["slug"] }

    @err = StringIO.new
    assert_equal 2, invoke("search", "@one")
    assert_match(/Usage: okf search/, @err.string)
  end

  test "server with no dir serves the persistent registry behind a hub" do
    write("one/a.md", concept)
    OKF::CLI.start([ "registry", "set", File.join(@tmpdir, "one") ], out: @out, err: @err)
    captured = []
    cli = OKF::CLI.new(out: @out, err: @err, runner: ->(app, host, port) { captured << [ app, host, port ] })

    assert_equal 0, cli.run([ "server" ])
    assert_kind_of OKF::Server::Hub, booted_app(captured.first.first)
    assert_match(/serving 1 bundle/, @out.string)
  end

  private

  # Every boot goes out through the gzip wrap, so a test asking *which* app was
  # booted looks through it — and asserts the wrap on the way, which is what keeps
  # a hub from quietly losing the compression a single bundle gets.
  def booted_app(app)
    assert_kind_of Rack::Deflater, app, "the boot seam gzips whatever it serves"
    app.instance_variable_get(:@app)
  end

  def invoke(*argv)
    OKF::CLI.start(argv, out: @out, err: @err)
  end

  # @refs resolve through $OKF_HOME; point it at the test registry for a block
  # so no test ever touches the real ~/.okf.
  # Point $OKF_HOME somewhere else for the block — the CLI's only lever on which
  # registry it reads. teardown restores the scratch one either way.
  def with_home(dir)
    was = ENV.fetch("OKF_HOME", nil)
    ENV["OKF_HOME"] = dir
    yield
  ensure
    was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = was
  end

  def concept(title = "A")
    "---\ntype: Note\ntitle: #{title}\ndescription: d\n---\n\nhi\n"
  end

  # A tiny bundle for the catalog/files/tags/stats views: two areas, three
  # concepts, a two-edge chain (mission → a → b), and shared/unique tags.
  def build_sample
    write("product/mission.md", "---\ntype: Mission\ntitle: Mission\ntags: [m, okf]\n---\n\n[Alpha](/features/a.md)\n")
    write("features/a.md", "---\ntype: Feature\ntitle: Alpha\nstatus: shipped\ntags: [x, okf]\n---\n\n[Beta](/features/b.md)\n")
    write("features/b.md", "---\ntype: Feature\ntitle: Beta\ntags: [x]\n---\n\nleaf\n")
  end

  def write(path, content)
    target = File.join(@tmpdir, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
  end
end

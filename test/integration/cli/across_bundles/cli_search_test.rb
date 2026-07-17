# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf search` naming SEVERAL bundles — the verb's real multi-bundle mode, and
# the whole surface of it. A plain dir answers about one bundle; leading @refs or
# --all merge N bundles into one ranking, label every row with the bundle it came
# from, and switch the JSON to an envelope whose head maps slug → dir. The
# ranking is the load-bearing claim: scores are absolute term weights, so a row
# from one bundle compares to a row from another, and ties break deterministically
# (score, then slug, then id) no matter what order the refs were typed.
module AcrossBundles
  # Bundles named several at a time — merged retrieval.
  class CLISearchTest < CLIIntegrationCase
    # -- the form that switches the mode

    test "several @refs merge into one ranking and label every row with its bundle" do
      with_registry("conformant", "rooted") do
        result = okf("search", "@conformant", "@rooted", "the")

        assert_equal 0, result.status
        assert_match(/Search — @conformant @rooted · the \(5 concepts\)/, result.out,
          "the header names every bundle searched, in the order they were typed")
        assert_match(%r{@conformant\s+datasets/sales\s+Sales}, result.out)
        assert_match(/@rooted\s+charter\s+Charter/, result.out,
          "a row names its bundle, so an id is never ambiguous across bundles")
      end
    end

    test "a single @ref is still registry mode — the envelope switches on form, not count" do
      with_registry("mentions") do
        human = okf("search", "@mentions", "payments")
        assert_equal 0, human.status
        assert_match(/Search — @mentions · payments \(2 concepts\)/, human.out)
        assert_match(/@mentions\s+ownership\s+Ownership/, human.out, "one bundle still labels its rows")

        data = json(okf("search", "@mentions", "payments", "--json"))
        assert_equal %w[bundles query count matches], data.keys,
          "one ref gets the multi-bundle envelope — the form decided, not the count"
        assert_equal [ "mentions" ], data["bundles"].map { |bundle| bundle["slug"] }
        assert_equal %w[mentions mentions], data["matches"].map { |row| row["slug"] }
      end
    end

    test "a dir cannot join the refs — only leading @refs name bundles, the rest are terms" do
      with_registry("conformant") do
        # A leading @ref chose registry mode; every later positional is a term.
        # So a dir typed after a ref is searched for as *text* — it never becomes
        # a second bundle, and the answer stays about the one bundle asked for.
        result = okf("search", "@conformant", fixture("rooted"), "--json")

        assert_equal 0, result.status
        assert_equal [ "conformant" ], json(result)["bundles"].map { |bundle| bundle["slug"] },
          "the trailing dir never became a second bundle"
        assert_equal 0, json(result)["count"], "it was searched for as a literal path, which nothing says"
      end
    end

    # -- the JSON envelope

    test "the JSON head maps slug to dir, so a row resolves to a file with no second lookup" do
      with_registry("conformant", "mentions") do
        data = json(okf("search", "@conformant", "@mentions", "the", "--json"))

        assert_equal %w[bundles query count matches], data.keys
        assert_equal [ "the" ], data["query"]
        assert_equal data["matches"].size, data["count"]

        dirs = data["bundles"].map { |bundle| [ bundle["slug"], bundle["dir"] ] }.to_h
        assert_equal({ "conformant" => fixture("conformant"), "mentions" => fixture("mentions") }, dirs)

        refute_empty data["matches"]
        data["matches"].each do |row|
          assert dirs.key?(row["slug"]), "every row carries a slug the head maps: #{row["slug"]}"
          # The claim, exercised rather than asserted: <dir>/<id>.md is the file.
          path = File.join(dirs[row["slug"]], "#{row["id"]}.md")
          assert_path_exists path
          assert_match(/^title: #{Regexp.escape(row["title"])}$/, read_utf8(path),
            "the row resolved to the concept it describes")
        end
      end
    end

    test "search --pretty implies --json and indents the multi-bundle envelope" do
      with_registry("conformant", "rooted") do
        result = okf("search", "@conformant", "@rooted", "the", "--pretty")

        assert_equal 0, result.status
        assert_match(/\n\s+"bundles"/, result.out, "--pretty indents without needing --json spelled out")
        assert_match(/\n\s+"matches"/, result.out)
        assert_equal 5, JSON.parse(result.out)["count"]
      end
    end

    # -- merged ranking: the load-bearing claim

    test "merged ranking orders by absolute term weight, so scores compare across bundles" do
      with_registry("conformant", "rooted", "minimal") do
        data = json(okf("search", "@conformant", "@rooted", "@minimal", "the", "--json"))
        scores = data["matches"].map { |row| row["score"] }

        assert_equal scores.sort.reverse, scores, "a merged ranking stays ordered by score"
        # The interleave is the proof: bundles alternate down the list, so the
        # order is the score's doing and not a per-bundle concatenation.
        assert_equal %w[conformant rooted rooted minimal conformant conformant],
          data["matches"].map { |row| row["slug"] }
        assert_operator scores.first, :>, scores.last
      end
    end

    test "ties break deterministically: score, then slug, then id" do
      with_registry("conformant", "rooted") do
        rows = json(okf("search", "@conformant", "@rooted", "the", "--json"))["matches"]
        tied = rows.select { |row| row["score"] == 3 }.map { |row| "#{row["slug"]}/#{row["id"]}" }

        assert_equal 3, tied.size, "three concepts score 3 — the tie the ordering has to resolve"
        assert_equal [ "conformant/datasets/sales", "rooted/charter", "rooted/services/gateway" ], tied,
          "equal scores order by slug (conformant < rooted), then by id (charter < services/gateway)"
      end
    end

    test "the ranking is stable across the ref order typed; only the head follows argv" do
      with_registry("conformant", "rooted", "minimal") do
        typed = json(okf("search", "@conformant", "@rooted", "@minimal", "the", "--json"))
        reversed = json(okf("search", "@minimal", "@rooted", "@conformant", "the", "--json"))

        assert_equal typed["matches"], reversed["matches"],
          "ref order is not a ranking input — the same question gets the same answer"
        assert_equal %w[conformant rooted minimal], typed["bundles"].map { |bundle| bundle["slug"] }
        assert_equal %w[minimal rooted conformant], reversed["bundles"].map { |bundle| bundle["slug"] },
          "the head reports what was asked for, in the order it was asked"
      end
    end

    test "refs dedupe by resolved path, not by spelling — bare @ and its slug are one bundle" do
      with_registry("conformant", "minimal") do
        okf("registry", "default", "conformant", "--home", @home)
        data = json(okf("search", "@", "@conformant", "the", "--json"))

        assert_equal [ "conformant" ], data["bundles"].map { |bundle| bundle["slug"] },
          "bare @ is the default bundle — naming it twice searches it once"
        assert_equal 3, data["count"], "no row is counted twice"
      end
    end

    # -- --all

    test "search --all covers every registered bundle" do
      with_registry("conformant", "rooted", "minimal") do
        result = okf("search", "--all", "the", "--json")

        assert_equal 0, result.status
        assert_equal %w[conformant rooted minimal], json(result)["bundles"].map { |bundle| bundle["slug"] },
          "--all takes the registry in its own order"
        assert_equal 6, json(result)["count"]
      end
    end

    test "search --all with @refs alongside is a usage error" do
      with_registry("conformant", "minimal") do
        result = okf("search", "--all", "@conformant", "the")

        assert_equal 2, result.status
        assert_match(/error: --all already searches every registered bundle; drop the @refs or the flag/, result.err)
        assert_match(/note: searching for a literal @-term\?/, result.err, "the note names the way out for a literal @-term")
        assert_empty result.out, "a usage error leaves stdout clean"
      end
    end

    test "search --all takes no directory: a dir positional searches as a literal term, with a note" do
      with_registry("conformant", "minimal") do
        # Under --all every positional IS a term, so a first arg that happens to
        # name a directory is legitimate ("lib", "docs" from a project root).
        # Refusing it would make the command's fate depend on the cwd it ran in.
        result = okf("search", "--all", fixture("conformant"), "the")

        assert_equal 0, result.status
        assert_match(/note: '#{Regexp.escape(fixture("conformant"))}' searches as a literal term — --all takes no directory/, result.err)
        assert_match(/no matches/, result.out, "it searched for the path as text, and no concept says it")
      end
    end

    test "search --all with an empty registry is a usage error, not an empty answer" do
      result = okf("search", "--all", "the", "--home", @home)

      assert_equal 2, result.status
      assert_match(/error: no bundles registered \(okf registry set <dir>\)/, result.err)
      assert_empty result.out
    end

    test "search --all skips a registered bundle whose directory is gone, and answers from the rest" do
      gone = File.join(@out_dir, "gone")
      FileUtils.cp_r(fixture("minimal"), gone)
      okf("registry", "set", fixture("conformant"), "--home", @home)
      okf("registry", "set", gone, "--home", @home)
      FileUtils.rm_rf(gone)

      result = okf("search", "--all", "the", "--json", "--home", @home)

      assert_equal 0, result.status, "one stale entry does not sink the search — the same forgiveness the hub shows"
      assert_match(/note: skipping gone — cannot read #{Regexp.escape(gone)}/, result.err)
      # The note went to stderr, so stdout is still a clean JSON document.
      data = json(result)
      assert_equal [ "conformant" ], data["bundles"].map { |bundle| bundle["slug"] }
      assert_equal 3, data["count"]
    end

    test "search --all fails when every registered bundle is missing on disk" do
      gone = File.join(@out_dir, "vanished")
      FileUtils.cp_r(fixture("minimal"), gone)
      okf("registry", "set", gone, "--home", @home)
      FileUtils.rm_rf(gone)

      result = okf("search", "--all", "the", "--home", @home)

      assert_equal 2, result.status, "nothing left to search is a usage error, not a silent zero-match"
      assert_match(/note: skipping vanished/, result.err)
      assert_match(/error: every registered bundle is missing on disk \(okf registry list\)/, result.err)
      assert_empty result.out
    end

    # -- every flag, in multi form

    test "search --fields projects literally, so --fields id drops the slug label" do
      with_registry("conformant", "rooted") do
        # The footgun, asserted rather than warned about: projection is literal.
        # A row projected to `id` alone no longer says which bundle it came from,
        # and ids repeat across bundles — ask for slug when you project.
        lean = json(okf("search", "@conformant", "@rooted", "the", "--fields", "id"))
        assert_equal [ "id" ], lean["matches"].first.keys
        refute lean["matches"].first.key?("slug"), "--fields id drops the label that made the row resolvable"

        labeled = json(okf("search", "@conformant", "@rooted", "the", "--fields", "id,slug,score"))
        assert_equal %w[slug id score], labeled["matches"].first.keys,
          "projection is a filter, not a reorder — the row keeps the envelope's key order"
        assert_equal "conformant", labeled["matches"].first["slug"]

        assert_equal 5, lean["count"], "projection trims the rows, never the answer"
      end
    end

    test "search --except is the complement, and the two conflict" do
      with_registry("conformant", "rooted") do
        trimmed = json(okf("search", "@conformant", "@rooted", "the", "--except", "snippet,matched"))
        first = trimmed["matches"].first
        refute first.key?("snippet")
        refute first.key?("matched")
        assert_equal "conformant", first["slug"], "--except keeps the label that resolves the row"

        clash = okf("search", "@conformant", "@rooted", "the", "--fields", "id", "--except", "score")
        assert_equal 2, clash.status
        assert_match(/error: --fields and --except are mutually exclusive/, clash.err)

        bogus = okf("search", "@conformant", "@rooted", "the", "--fields", "nope")
        assert_equal 2, bogus.status
        assert_match(/error: unknown field\(s\): nope \(available: slug, id, title, type, area, tags, matched, score, snippet\)/,
          bogus.err, "the available list names slug — the field the multi-bundle envelope adds")
      end
    end

    test "search -e treats terms as regexps across every bundle; a bad pattern is a usage error" do
      with_registry("conformant", "mentions") do
        hit = json(okf("search", "@conformant", "@mentions", "-e", "^sale", "--json"))
        assert_equal [ "conformant" ], hit["matches"].map { |row| row["slug"] }.uniq,
          "the pattern ran against both bundles; only one has an anchored hit"
        assert_equal 3, hit["count"]

        bad = okf("search", "@conformant", "@mentions", "-e", "[unclosed")
        assert_equal 2, bad.status
        assert_match(/error: invalid pattern: premature end of char-class/, bad.err)
        assert_empty bad.out, "one bad pattern sinks the run before any bundle is read"
      end
    end

    test "search --in narrows the searched fields in every bundle; an unknown field lists the real ones" do
      with_registry("conformant", "mentions") do
        scoped = json(okf("search", "@conformant", "@mentions", "payments", "--in", "tags", "--json"))
        assert_equal %w[escalation ownership], scoped["matches"].map { |row| row["id"] }.sort
        assert_equal [ [ "tags" ] ], scoped["matches"].map { |row| row["matched"] }.uniq,
          "only the tag hit is credited when the search is scoped to it"

        bogus = okf("search", "@conformant", "@mentions", "payments", "--in", "bogus")
        assert_equal 2, bogus.status
        assert_match(/error: unknown field\(s\): bogus \(searchable: title, id, tags, type, description, body\)/, bogus.err)
        assert_empty bogus.out
      end
    end

    test "search filters apply per bundle and narrow the candidates before the merge" do
      with_registry("conformant", "rooted", "mentions") do
        # --area is resolved inside each bundle: "(root)" means every bundle's own root.
        rooted_area = json(okf("search", "--all", "the", "--area", "root", "--json"))
        assert_equal [ "mentions/ownership", "rooted/charter", "mentions/escalation" ],
          rooted_area["matches"].map { |row| "#{row["slug"]}/#{row["id"]}" },
          "each bundle contributed only its own root-area concepts"

        typed = json(okf("search", "--all", "the", "--type", "BigQuery Table", "--json"))
        assert_equal [ "conformant" ], typed["matches"].map { |row| row["slug"] }.uniq,
          "a type only one bundle uses narrows the merge to that bundle"

        tagged = json(okf("search", "--all", "the", "--tag", "shared", "--json"))
        assert_equal %w[charter services/gateway], tagged["matches"].map { |row| row["id"] }

        none = okf("search", "--all", "the", "--tag", "nothing-carries-this", "--json")
        assert_equal 0, none.status, "a filter matching nothing is still an advisory read"
        assert_equal 0, json(none)["count"]
        assert_equal 3, json(none)["bundles"].size, "the head still reports what was searched"
      end
    end

    # -- the @ grammar

    test "an unknown @ref among several fails hard and names the registry it consulted" do
      with_registry("conformant", "minimal") do
        result = okf("search", "@conformant", "@ghost", "@minimal", "the")

        assert_equal 2, result.status, "an explicit ask fails hard — never a silent skip like --all's"
        assert_match(/error: not a registered bundle: @ghost in .*registry\.json \(okf registry list\)/, result.err,
          "the message names the file it read, so a mismatch self-diagnoses")
        assert_match(/note: searching for a literal @-term\?/, result.err,
          "an unknown slug is plausibly a mistyped term, so the way out is offered")
        assert_empty result.out, "no bundle was searched — nothing half-answers"
      end
    end

    test "a registered-but-gone @ref among several fails hard, and gets no grammar hint" do
      gone = File.join(@out_dir, "removed")
      FileUtils.cp_r(fixture("minimal"), gone)
      okf("registry", "set", fixture("conformant"), "--home", @home)
      okf("registry", "set", gone, "--home", @home)
      FileUtils.rm_rf(gone)

      result = okf("search", "@conformant", "@removed", "the", "--home", @home)

      assert_equal 2, result.status, "--all would skip this entry; an explicit ask must not"
      assert_match(/error: @removed points to #{Regexp.escape(gone)}, which is not a directory/, result.err)
      assert_match(/okf registry del removed, or restore it/, result.err, "the message names the next move")
      refute_match(/searching for a literal @-term/, result.err,
        "a gone directory has nothing to do with the grammar — only an unknown slug is plausibly a mistyped term")
      assert_empty result.out
    end

    test "@refs must lead: a later @arg searches as a literal term, with a note" do
      with_registry("conformant", "minimal") do
        result = okf("search", "@conformant", "the", "@minimal")

        assert_equal 0, result.status, "a trailing @arg is a term, not a ref — no bundle was misread"
        assert_match(/note: '@minimal' searches as a literal term — @refs must lead/, result.err)
        assert_equal [ "conformant" ], json(okf("search", "@conformant", "the", "@minimal", "--json"))["bundles"].map { |b| b["slug"] },
          "@minimal never joined the search, even though it is registered"
        assert_match(/no matches/, result.out)
      end
    end

    test "a literal @term is reachable two ways: -e '\\@term', or a non-@ term first" do
      with_registry("conformant", "mentions") do
        # The mentions fixture exists for exactly this: prose carrying @-handles,
        # so the escape hatches can be shown to *find* something.
        escaped = json(okf("search", "--all", "-e", "\\@payments-oncall", "--json"))
        assert_equal [ "mentions/escalation" ], escaped["matches"].map { |row| "#{row["slug"]}/#{row["id"]}" },
          "-e '\\@term' gets the @ past the ref grammar and onto the text"

        leading_term = okf("search", "--all", "escalation", "@payments-oncall")
        assert_equal 0, leading_term.status
        assert_match(/note: '@payments-oncall' searches as a literal term — @refs must lead/, leading_term.err)
        assert_match(/@mentions\s+escalation\s+Escalation/, leading_term.out,
          "a non-@ term first demotes the @arg to a term, and the ANDed pair still finds the concept")
      end
    end

    # -- zero terms

    test "zero terms is a usage error in both multi-bundle forms" do
      with_registry("conformant", "minimal") do
        refs = okf("search", "@conformant", "@minimal")
        assert_equal 2, refs.status
        assert_match(/Usage: okf search <bundle-dir\|@ref…> <term> \[term \.\.\.\]/, refs.err)
        assert_empty refs.out, "no terms, no ranking — and no empty answer that looks like one"

        every = okf("search", "--all")
        assert_equal 2, every.status
        assert_match(/Usage: okf search <bundle-dir\|@ref…> <term> \[term \.\.\.\]/, every.err)
        assert_empty every.out
      end
    end

    # -- best effort

    test "a malformed bundle among several is best-effort: noted on stderr, stdout stays parseable" do
      with_registry("conformant", "malformed") do
        result = okf("search", "@conformant", "@malformed", "good", "--json")

        assert_equal 0, result.status
        assert_match(/note: skipped 2 file\(s\) with invalid frontmatter \(run `okf validate` for details\)/, result.err)
        data = json(result)
        assert_equal [ "malformed" ], data["matches"].map { |row| row["slug"] },
          "the concepts that parsed are still searched and still labeled"
        assert_equal "good", data["matches"].first["id"]
      end
    end
  end
end

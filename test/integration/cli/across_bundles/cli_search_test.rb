# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf search` naming SEVERAL bundles — the verb's real multi-bundle mode, and
# the whole surface of it. A plain dir answers about one bundle; leading @refs or
# @all merge N bundles into one ranking, label every row with the bundle it came
# from, and switch the JSON to an envelope whose head maps slug → dir. The
# ranking is the load-bearing claim: the bundles go into **one** index, so a row
# from one compares to a row from another by construction rather than by luck,
# and ties break deterministically (score, then slug, then id) no matter what
# order the refs were typed. (Before the index landed, scores were absolute field
# weights that happened to compare; one corpus is what replaced that accident.)
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

    test "several @refs resolve through a discovered local registry" do
      tree = File.join(@out_dir, "search-proj")
      FileUtils.mkdir_p(tree)
      File.write(File.join(tree, ".okf-registry.json"), JSON.generate("bundles" => [], "groups" => []))
      in_dir(tree) do
        okf("registry", "set", fixture("conformant"))
        okf("registry", "set", fixture("rooted"))
      end

      result = in_dir(tree) { okf("search", "@conformant", "@rooted", "the") }

      assert_equal 0, result.status
      assert_match(/Search — @conformant @rooted · the \(5 concepts\)/, result.out,
        "both refs resolved through the local registry, and merged into one ranking")
      assert_match(/@rooted\s+charter\s+Charter/, result.out)
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

    test "merged ranking comes from one index, so the scores compare" do
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

    test "the searched bundles are one corpus: a score is relative to the whole answer" do
      with_registry("conformant", "rooted", "minimal") do
        # BM25 prices a term by how rare it is, so the corpus is an input to every
        # score. Searching a bundle alone and searching it in company must
        # therefore price the same concept differently — and that difference is the
        # observable proof the merge ranks *one* corpus instead of splicing three
        # independent rankings, which is exactly what would make the numbers
        # incomparable while still looking like a sorted list.
        #
        # Named explicitly because this is a *BM25* property, not a merge property:
        # the default scan scores by absolute field weight, so its numbers do not
        # move with the corpus and are comparable across bundles by construction.
        # Testing this through the default would assert nothing.
        solo_run = okf("search", "@conformant", "the", "--engine", "index", "--json")
        joint_run = okf("search", "@conformant", "@rooted", "@minimal", "the", "--engine", "index", "--json")

        solo = json(solo_run)["matches"].find { |row| row["id"] == "datasets/sales" }["score"]
        joint = json(joint_run)["matches"].find { |row| row["id"] == "datasets/sales" }["score"]

        assert_operator solo, :>, joint,
          "'the' is commoner across three bundles than in one, so the same row is worth less in company"
      end
    end

    test "the default merge needs no corpus: a score is the same alone or in company" do
      with_registry("conformant", "rooted", "minimal") do
        # The mirror of the test above, and the reason the swap does not weaken the
        # merge. The scan scores by field weight alone, so a row is worth exactly
        # the same whether it was searched by itself or beside two other bundles —
        # comparable across bundles without needing one shared corpus at all.
        alone = json(okf("search", "@conformant", "the", "--json"))["matches"]
        merged = json(okf("search", "@conformant", "@rooted", "@minimal", "the", "--json"))["matches"]

        solo = alone.find { |row| row["id"] == "datasets/sales" }["score"]
        joint = merged.find { |row| row["id"] == "datasets/sales" }["score"]

        assert_equal solo, joint, "a field-weight score has no corpus term to move"
      end
    end

    test "ties break deterministically: score, then slug, then id" do
      with_registry("conformant", "rooted") do
        # A BM25 score is a float off per-document statistics and practically never
        # ties. The regexp path still scores by absolute field weight, so it is
        # where equal scores actually occur — and where the rule stays observable.
        rows = json(okf("search", "@conformant", "@rooted", "-e", "the", "--json"))["matches"]
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
        okf("registry", "default", "conformant")
        data = json(okf("search", "@", "@conformant", "the", "--json"))

        assert_equal [ "conformant" ], data["bundles"].map { |bundle| bundle["slug"] },
          "bare @ is the default bundle — naming it twice searches it once"
        assert_equal 3, data["count"], "no row is counted twice"
      end
    end

    # -- @all

    test "search @all covers every registered bundle" do
      with_registry("conformant", "rooted", "minimal") do
        result = okf("search", "@all", "the", "--json")

        assert_equal 0, result.status
        assert_equal %w[conformant rooted minimal], json(result)["bundles"].map { |bundle| bundle["slug"] },
          "@all takes the registry in its own order"
        assert_equal 6, json(result)["count"]
      end
    end

    test "search @all alongside a named ref expands and dedupes — all ⊇ one, so there is nothing to warn about" do
      with_registry("conformant", "minimal") do
        both = json(okf("search", "@all", "@conformant", "the", "--json"))
        alone = json(okf("search", "@all", "the", "--json"))

        assert_equal %w[conformant minimal], both["bundles"].map { |bundle| bundle["slug"] },
          "@conformant is already in @all, so it is searched once, not twice"
        assert_equal alone["count"], both["count"]
      end
    end

    test "search @all is a ref, so a directory in slot 1 is still a directory" do
      with_registry("conformant", "minimal") do
        # The point of making "every bundle" a ref: slot 1 always means a bundle
        # identity, so a dir there is a dir and no flag can flip what it means.
        result = okf("search", fixture("conformant"), "the")

        assert_equal 0, result.status
        refute_match(/searches as a literal term/, result.err, "no flip, so nothing to explain")
        assert_match(/Search — #{Regexp.escape(fixture("conformant"))}/, result.out, "a plain dir keeps the single-bundle output")
      end
    end

    test "search @all with an empty registry is a usage error, not an empty answer" do
      result = okf("search", "@all", "the")

      assert_equal 2, result.status
      assert_match(/error: no bundles registered \(okf registry set <dir>\)/, result.err)
      assert_empty result.out
    end

    test "search @all skips a registered bundle whose directory is gone, and answers from the rest" do
      gone = File.join(@out_dir, "gone")
      FileUtils.cp_r(fixture("minimal"), gone)
      okf("registry", "set", fixture("conformant"))
      okf("registry", "set", gone)
      FileUtils.rm_rf(gone)

      result = okf("search", "@all", "the", "--json")

      assert_equal 0, result.status, "one stale entry does not sink the search — the same forgiveness the hub shows"
      assert_match(/note: skipping gone — cannot read #{Regexp.escape(gone)}/, result.err)
      # The note went to stderr, so stdout is still a clean JSON document.
      data = json(result)
      assert_equal [ "conformant" ], data["bundles"].map { |bundle| bundle["slug"] }
      assert_equal 3, data["count"]
    end

    test "asking for everything tolerates a gap; naming one bundle demands it" do
      gone = File.join(@out_dir, "gone")
      FileUtils.cp_r(fixture("minimal"), gone)
      okf("registry", "set", fixture("conformant"))
      okf("registry", "set", gone)
      FileUtils.rm_rf(gone)

      tolerated = okf("search", "@all", "the", "--json")
      named = okf("search", "@gone", "the")

      assert_equal 0, tolerated.status, "@all skips what it cannot read"
      assert_equal 2, named.status, "@gone insists on the bundle it names"
      assert_match(/error: @gone points to #{Regexp.escape(gone)}, which is not a directory/, named.err)
    end

    test "search @all fails when every registered bundle is missing on disk" do
      gone = File.join(@out_dir, "vanished")
      FileUtils.cp_r(fixture("minimal"), gone)
      okf("registry", "set", gone)
      FileUtils.rm_rf(gone)

      result = okf("search", "@all", "the")

      assert_equal 2, result.status, "nothing left to search is a usage error, not a silent zero-match"
      assert_match(/note: skipping vanished/, result.err)
      assert_match(/error: every registered bundle is missing on disk \(okf registry list\)/, result.err)
      assert_empty result.out
    end

    test "an unknown flag is a usage error before any bundle is read" do
      with_registry("conformant", "minimal") do
        result = okf("search", "@all", "--bogus", "the")

        assert_equal 2, result.status
        assert_match(/invalid option: --bogus/, result.err)
        assert_empty result.out, "the ask was not understood, so no ranking is printed"
      end
    end

    test "@all is normalized like every other ref — @ALL and @All name every bundle too" do
      with_registry("conformant", "rooted", "minimal") do
        canonical = json(okf("search", "@all", "the", "--json"))
        refute_empty canonical["bundles"], "the canonical spelling has to answer for the comparison to mean anything"

        %w[@ALL @All @aLL].each do |spelling|
          result = okf("search", spelling, "the", "--json")

          assert_equal 0, result.status, spelling
          assert_equal canonical["bundles"], json(result)["bundles"], "#{spelling} expands exactly as @all does"
          assert_equal canonical["count"], json(result)["count"], spelling
        end
      end
    end

    test "the refusal is normalized too: `lint @ALL` is refused by name, not called unknown" do
      with_registry("conformant", "minimal") do
        result = okf("lint", "@ALL")

        assert_equal 2, result.status
        assert_match(/error: @all is only supported by `okf search`/, result.err,
          "the message names the canonical spelling, whatever spelling was typed")
        refute_match(/not a registered bundle/, result.err,
          "`all` is reserved and can never be registered, so sending the user to `registry list` to look for it is a dead end")
      end
    end

    test "@all is normalized, not merely downcased — @a-l-l is a bundle nobody registered" do
      with_registry("conformant") do
        # The ref grammar has one normalization and @all goes through it, which is
        # what makes @ALL work. It is `Registry.normalize`, though — not a
        # downcase — so only what normalizes *to* `all` is @all.
        result = okf("search", "@a-l-l", "the")

        assert_equal 2, result.status
        assert_match(/error: not a registered bundle: @a-l-l/, result.err)
      end
    end

    test "@all is search's alone — every other bundle-taking verb refuses it by name" do
      # It must not resolve through the shared ref path: there it would yield one
      # bundle when one is registered (and lint it) and two when two are (exit 2),
      # so the same command's meaning would track the size of the registry.
      with_registry("conformant", "minimal") do
        %w[lint validate loose index dirs catalog files tags types stats graph render server].each do |verb|
          result = okf(verb, "@all")

          assert_equal 2, result.status, "#{verb} @all"
          assert_match(/error: @all is only supported by `okf search` \(it names every registered bundle\)/, result.err, verb)
          assert_empty result.out, verb
        end
      end
    end

    test "a bundle can never be slugged `all`, so @all is never ambiguous" do
      named = fixture("all") # a fixture whose directory name is the reserved word

      explicit = okf("registry", "set", named, "--as", "all")
      assert_equal 2, explicit.status
      assert_match(/error: not a usable slug: all is reserved \(@all names every registered bundle\)/, explicit.err)

      # Minted from the basename, the gem may invent a name — so it suffixes
      # rather than refuses, the same rule as any other collision.
      assert_equal 0, okf("registry", "set", named).status
      assert_equal [ "all-2" ], json(okf("registry", "list", "--json"))["bundles"].map { |row| row["slug"] }
    end

    test "the ref grammar's own name is the one the registry refuses to mint" do
      # Derived from ALL_REF rather than spelled "all", so renaming the ref cannot
      # leave the registry happily minting the name the grammar just took.
      reserved = OKF::CLI::ALL_REF[1..-1]

      result = okf("registry", "set", fixture("all"), "--as", reserved)

      assert_equal 2, result.status, "@#{reserved} would be ambiguous if a bundle could answer to #{reserved}"
      assert_match(/error: not a usable slug: #{Regexp.escape(reserved)} is reserved/, result.err)
    end

    # -- every flag, in multi form

    test "--dir narrows every bundle in the merge, by the same prefix rule" do
      with_registry("conformant", "edge-cases") do
        scoped = json(okf("search", "@conformant", "@edge-cases", "concept", "orders", "--dir", "root", "--json"))

        assert_equal 0, scoped["matches"].count { |row| row["dir"].start_with?("deeply") },
          "the filter is per-bundle, but the rule it applies is the same one everywhere"
        assert scoped["matches"].all? { |row| row["dir"] == "." }
      end
    end

    test "every merged row carries its dir, and --area still warns once for the whole merge" do
      with_registry("conformant", "edge-cases") do
        rows = json(okf("search", "@conformant", "@edge-cases", "concept", "--json"))["matches"]
        assert_includes rows.map { |row| row["dir"] }, "deeply/nested/path"

        warned = okf("search", "@conformant", "@edge-cases", "concept", "--area", "root", "--json")
        assert_equal "warning: --area is deprecated, use --dir\n", warned.err,
          "one run, one warning — not one per bundle searched"
      end
    end

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
        assert_match(/error: unknown field\(s\): nope \(available: slug, id, title, type, dir, area, tags, matched, score, snippet\)/,
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

    test "one engine answers the whole merge, chosen by the query and never announced" do
      # The merge is where a per-engine result would do the most damage: two
      # engines scoring two halves of one list would produce a ranking that means
      # nothing. One query, one engine, one corpus — and the score shape is what
      # makes which engine ran observable, since nothing says so.
      with_registry("conformant", "mentions") do
        index = json(okf("search", "@conformant", "@mentions", "sales", "--engine", "index", "--json"))
        scan = json(okf("search", "@conformant", "@mentions", "-e", "sales", "--json"))

        scan["matches"].each do |row|
          assert_equal weight_sum(row["matched"]), row["score"],
            "-e routes the whole merge to the scan, not just the first bundle"
        end
        index["matches"].each do |row|
          refute_equal weight_sum(row["matched"]), row["score"],
            "every row of the merge came from the index, including the ones from the second bundle"
        end

        human = okf("search", "@conformant", "@mentions", "-e", "sales")
        assert_empty human.err, "choosing an engine is not a diagnostic"
        assert_equal %w[bundles query count matches], scan.keys,
          "the multi-bundle envelope gains no engine key"
      end
    end

    test "search --engine names one engine for the whole merge, not one per bundle" do
      with_registry("conformant", "mentions") do
        merged = okf("search", "@conformant", "@mentions", "--engine", "scan", "sales", "--json")
        assert_equal 0, merged.status

        data = json(merged)
        data["matches"].each do |row|
          assert_equal weight_sum(row["matched"]), row["score"],
            "every row of the merge came from the named engine, whichever bundle it came from"
        end
        assert_equal %w[bundles query count matches], data.keys, "naming an engine adds no key to the envelope"

        clash = okf("search", "@conformant", "@mentions", "--engine", "index", "-e", "^sale")
        assert_equal 2, clash.status
        assert_match(/error: --engine index does not support --regexp/, clash.err)
        assert_empty clash.out, "one impossible pairing sinks the run before any bundle is read"
      end
    end

    test "search --fuzzy forgives a typo in every bundle, and refuses to pair with -e" do
      with_registry("conformant", "rooted") do
        exact = okf("search", "@conformant", "@rooted", "gatway", "custommer", "--json")
        assert_equal 0, json(exact)["count"], "exact by default, so neither typo lands"

        fuzzy = json(okf("search", "@conformant", "@rooted", "gatway", "--fuzzy", "--json"))
        assert_equal [ "rooted" ], fuzzy["matches"].map { |row| row["slug"] }.uniq,
          "the tolerance is applied across the merge, not just to the first bundle"
        assert_includes fuzzy["matches"].map { |row| row["id"] }, "services/gateway"

        clash = okf("search", "@conformant", "@rooted", "gatway", "--fuzzy", "-e")
        assert_equal 2, clash.status
        assert_match(/error: --regexp and --fuzzy are mutually exclusive/, clash.err)
        assert_empty clash.out, "one contradictory pair sinks the run before any bundle is read"
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
        rooted_area = json(okf("search", "@all", "the", "--area", "root", "--json"))
        assert_equal [ "mentions/ownership", "rooted/charter", "mentions/escalation" ],
          rooted_area["matches"].map { |row| "#{row["slug"]}/#{row["id"]}" },
          "each bundle contributed only its own root-area concepts"

        typed = json(okf("search", "@all", "the", "--type", "BigQuery Table", "--json"))
        assert_equal [ "conformant" ], typed["matches"].map { |row| row["slug"] }.uniq,
          "a type only one bundle uses narrows the merge to that bundle"

        tagged = json(okf("search", "@all", "the", "--tag", "shared", "--json"))
        assert_equal %w[charter services/gateway], tagged["matches"].map { |row| row["id"] }

        none = okf("search", "@all", "the", "--tag", "nothing-carries-this", "--json")
        assert_equal 0, none.status, "a filter matching nothing is still an advisory read"
        assert_equal 0, json(none)["count"]
        assert_equal 3, json(none)["bundles"].size, "the head still reports what was searched"
      end
    end

    # -- the @ grammar

    test "an unknown @ref among several fails hard and names the registry it consulted" do
      with_registry("conformant", "minimal") do
        result = okf("search", "@conformant", "@ghost", "@minimal", "the")

        assert_equal 2, result.status, "an explicit ask fails hard — never a silent skip like @all's"
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
      okf("registry", "set", fixture("conformant"))
      okf("registry", "set", gone)
      FileUtils.rm_rf(gone)

      result = okf("search", "@conformant", "@removed", "the")

      assert_equal 2, result.status, "@all would skip this entry; an explicit ask must not"
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
        assert_match(/note: '@minimal' searches as a literal term — an @slug or @all must lead/, result.err)
        assert_equal [ "conformant" ], json(okf("search", "@conformant", "the", "@minimal", "--json"))["bundles"].map { |b| b["slug"] },
          "@minimal never joined the search, even though it is registered"
        assert_match(/no matches/, result.out)
      end
    end

    test "a literal @term is reachable two ways: -e '\\@term', or a non-@ term first" do
      with_registry("conformant", "mentions") do
        # The mentions fixture exists for exactly this: prose carrying @-handles,
        # so the escape hatches can be shown to *find* something.
        escaped = json(okf("search", "@all", "-e", "\\@payments-oncall", "--json"))
        assert_equal [ "mentions/escalation" ], escaped["matches"].map { |row| "#{row["slug"]}/#{row["id"]}" },
          "-e '\\@term' gets the @ past the ref grammar and onto the text"

        leading_term = okf("search", "@all", "escalation", "@payments-oncall")
        assert_equal 0, leading_term.status
        assert_match(/note: '@payments-oncall' searches as a literal term — an @slug or @all must lead/, leading_term.err)
        assert_match(/@mentions\s+escalation\s+Escalation/, leading_term.out,
          "a non-@ term first demotes the @arg to a term, and the ANDed pair still finds the concept")
      end
    end

    # -- zero terms

    test "zero terms is a usage error in both multi-bundle forms" do
      with_registry("conformant", "minimal") do
        refs = okf("search", "@conformant", "@minimal")
        assert_equal 2, refs.status
        assert_match(/Usage: okf search <dir\|@slug…\|@all> <term…>/, refs.err)
        assert_empty refs.out, "no terms, no ranking — and no empty answer that looks like one"

        every = okf("search", "@all")
        assert_equal 2, every.status
        assert_match(/Usage: okf search <dir\|@slug…\|@all> <term…>/, every.err)
        assert_empty every.out
      end
    end

    # -- groups: a named @ref that fans out to member bundles

    test "a group @ref searches its members, merged and labelled like the refs it stands for" do
      with_registry("conformant", "rooted") do
        okf("registry", "group", "docs", "@conformant", "@rooted")

        grouped = okf("search", "@docs", "the", "--json")
        spelled = okf("search", "@conformant", "@rooted", "the", "--json")

        assert_equal 0, grouped.status
        assert_equal json(spelled)["matches"].map { |row| [ row["slug"], row["id"] ] },
          json(grouped)["matches"].map { |row| [ row["slug"], row["id"] ] },
          "@docs resolves to exactly the two bundles it groups, ranked as one corpus"
      end
    end

    test "a group and an overlapping ref dedupe — the shared member is searched once" do
      with_registry("conformant", "rooted") do
        okf("registry", "group", "docs", "@conformant", "@rooted")

        data = json(okf("search", "@docs", "@conformant", "the", "--json"))

        assert_equal %w[conformant rooted], data["bundles"].map { |bundle| bundle["slug"] },
          "conformant, named by the group and again by @conformant, appears once"
      end
    end

    test "a vanished group member is skipped with a note, the rest still search" do
      doomed = scratch_bundle("doomed")
      with_registry("conformant") do
        okf("registry", "set", doomed)
        okf("registry", "group", "docs", "@conformant", "@doomed")
        FileUtils.rm_rf(doomed)

        result = okf("search", "@docs", "the", "--json")

        assert_equal 0, result.status
        assert_match(/note: skipping doomed — cannot read #{Regexp.escape(doomed)}/, result.err)
        assert_equal [ "conformant" ], json(result)["bundles"].map { |bundle| bundle["slug"] }
      end
    end

    test "a group whose every member vanished errors, not a silent empty search" do
      a = scratch_bundle("a")
      b = scratch_bundle("b")
      okf("registry", "set", a)
      okf("registry", "set", b)
      okf("registry", "group", "docs", "@a", "@b")
      FileUtils.rm_rf(a)
      FileUtils.rm_rf(b)

      result = okf("search", "@docs", "the")

      assert_equal 2, result.status
      assert_match(/@docs resolves to no readable bundle/, result.err)
      assert_empty result.out
    end

    # -- best effort

    test "a malformed bundle among several is best-effort: noted on stderr, stdout stays parseable" do
      with_registry("conformant", "malformed") do
        result = okf("search", "@conformant", "@malformed", "good", "--json")

        assert_equal 0, result.status
        assert_match(/note: skipped 2 unusable file\(s\) \(run `okf validate` for details\)/, result.err)
        data = json(result)
        assert_equal [ "malformed" ], data["matches"].map { |row| row["slug"] },
          "the concepts that parsed are still searched and still labeled"
        assert_equal "good", data["matches"].first["id"]
      end
    end
  end
end

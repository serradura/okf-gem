# frozen_string_literal: true

require "test_helper"

# The generator, and the six invariants §5 of the design holds it to.
#
# The scaffold is the one part of this gem an adopter meets before anything
# else, and every defect in it is a defect they inherit permanently: a bundle
# that does not lint on day zero teaches them the gate is noise, a shipped date
# ages into their calendar, a hook without +x is a gate git silently skips.
class ScaffoldTest < OKF::Pro::TestCase
  Result = Struct.new(:status, :out, :err)

  def setup_into(dir, verb: "setup")
    out = StringIO.new
    err = StringIO.new
    status = OKF::Pro::Scaffold.public_send(verb, dir, out: out, err: err)
    Result.new(status, out.string, err.string)
  end

  def in_empty(&block)
    Dir.mktmpdir("scaffold-", &block)
  end

  # ── invariant 2 — day zero passes, on every door ──────────────────────────

  def test_a_generated_bundle_is_conformant_on_day_zero
    in_empty do |dir|
      assert_equal OKF::Pro::PASS, setup_into(dir).status

      bundle = OKF::Bundle::Reader.read(File.join(dir, ".okf"))
      result = OKF::Bundle::Validator.call(bundle)

      assert result.valid?, "day zero must validate: #{result.errors.inspect}"
      assert_empty result.warnings, "day zero must validate without warnings: #{result.warnings.inspect}"
    end
  end

  def test_a_generated_bundle_lints_clean_at_fail_on_warn
    in_empty do |dir|
      setup_into(dir)
      report = OKF::Bundle::Linter.call(OKF::Bundle::Reader.read(File.join(dir, ".okf")),
        today: Date.today, except: [ :stale ])

      assert_empty report.warnings, "day zero must carry no warning: #{report.warnings.inspect}"
    end
  end

  def test_a_generated_bundle_passes_the_audit
    in_empty do |dir|
      setup_into(dir)

      assert_empty OKF::Pro::Audit.call(dir)
    end
  end

  # The stop gate is the door a session actually hits, and a generated bundle
  # must reach it without the gates having anything to say except the ritual
  # itself: no snapshot yet is the correct state, and the gate hands over the
  # computed line rather than a complaint about the template.
  def test_the_stop_gate_drill_asks_for_the_snapshot_and_nothing_else
    in_empty do |dir|
      setup_into(dir)
      system("git", "init", "-q", dir, out: File::NULL, err: File::NULL)
      system("git", "-C", dir, "add", "-A", out: File::NULL, err: File::NULL)

      messages = OKF::Pro::Closing.stop_gate(event(cwd: dir))

      assert_equal 1, messages.size, "the template itself must give the gate nothing to say: #{messages.inspect}"
      assert_match(/RULE 2/, messages.first)
      assert_match(/\*\*Snapshot\*\*: inbox 0/, messages.first)
    end
  end

  # The refusal cites `Audit.ambiguous_layout`, which asks `root_kind` — index.md
  # PLUS board.md/log.md, or an `okf_version` in the frontmatter. This asked
  # `bundle?`, which is index.md alone, so any Jekyll section, Hugo directory or
  # repo with an `index.md` README was told to `git mv` files that have nothing
  # to do with OKF, for an ambiguity the audit would never report.
  def test_setup_into_a_directory_holding_only_a_docs_index_is_not_refused
    in_empty do |dir|
      File.write(File.join(dir, "index.md"), "# just a docs index\n\nNothing to do with OKF.\n")

      out = StringIO.new
      err = StringIO.new
      status = OKF::Pro::Scaffold.setup(dir, out: out, err: err)

      assert_equal OKF::Pro::PASS, status, err.string
      assert OKF::Pro::BundleRoot.bundle?(File.join(dir, OKF::Pro::BundleRoot::DIR))
    end
  end

  def test_the_session_banner_reads_a_fresh_bundle_as_new_rather_than_broken
    in_empty do |dir|
      setup_into(dir)

      banner = Array(OKF::Pro::Closing.session_context(event(cwd: dir))).join("\n")

      assert_match(%r{in flight 0/5}, banner)
      assert_match(/Last snapshot: none yet/, banner)
    end
  end

  # ── invariant 3 — no date ships ───────────────────────────────────────────
  #
  # A template is cloned an unknowable number of days after it is built, and a
  # shipped date ages into somebody else's calendar. The journal guard locks a
  # foreign day-zero entry against correction forever, and — the failure that
  # decided this — dormancy measures a bundle's age by its OLDEST journal entry,
  # so a shipped entry makes a fresh clone read as an old bundle and the
  # adopter's first promotion draws a dormancy question it never earned.
  #
  # The exemption is required rather than cosmetic: projects/index.md teaches
  # the closure marker, and `Pairing::MARKER` requires a date, so the example
  # cannot lose it without teaching a spelling the gate rejects.
  def test_no_date_ships_outside_a_code_span
    in_empty do |dir|
      setup_into(dir)

      offenders = Dir.glob(File.join(dir, ".okf", "**", "*.md")).sort.flat_map do |path|
        dated_prose_lines(path).map { |line| "#{path.sub("#{dir}/", "")}: #{line}" }
      end

      assert_empty offenders,
        "a shipped date ages into the adopter's calendar; put it in a code span or remove it"
    end
  end

  # ── invariant 4 — the core is closed, roadmap.md is the one deletion ──────

  def test_removing_any_core_file_but_the_roadmap_is_reported
    in_empty do |dir|
      setup_into(dir)
      bundle = File.join(dir, ".okf")

      OKF::Pro::Audit::CORE.map(&:first).each do |rel|
        path = File.join(bundle, rel)
        moved = "#{path.chomp("/")}.moved"
        File.rename(path.chomp("/"), moved)
        findings = OKF::Pro::Audit.call(dir)
        assert_match(/#{Regexp.escape(rel)} is missing/, findings.join("\n"),
          "#{rel} is core; its absence must be reported by name")
        File.rename(moved, path.chomp("/"))
      end
    end
  end

  def test_the_roadmap_may_be_deleted_by_its_own_standing_accusation
    in_empty do |dir|
      setup_into(dir)
      bundle = File.join(dir, ".okf")
      File.unlink(File.join(bundle, "roadmap.md"))
      # Two moves, not one, and the file that invites the deletion says so: an
      # index still linking at a deleted file is a broken_index_entry, which is
      # exactly what lint is for.
      index = File.join(bundle, "index.md")
      File.write(index, OKF::Pro.read_text(index).lines.reject { |l| l.include?("roadmap.md") }.join)

      assert_empty OKF::Pro::Audit.call(dir),
        "roadmap.md is the one file the design lets an adopter remove"
    end
  end

  # ── invariant 5 — nothing references the template's own construction ──────

  def test_the_generated_tree_links_only_to_what_it_writes
    in_empty do |dir|
      setup_into(dir)
      written = Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH)
                   .select { |p| File.file?(p) }
                   .map { |p| p.sub("#{dir}/", "") }

      broken = Dir.glob(File.join(dir, ".okf", "**", "*.md")).flat_map do |path|
        OKF::Pro.read_text(path).scan(%r{\]\((/[^)#\s]+)\)}).flatten.map do |target|
          rel = ".okf#{target}"
          next if written.include?(rel) || written.any? { |w| w.start_with?("#{rel.chomp("/")}/") }

          "#{path.sub("#{dir}/", "")} → #{target}"
        end.compact
      end

      assert_empty broken, "the generated tree names a file the generator does not write"
    end
  end

  # ── invariant 6 — the generated list is what actually ships ───────────────

  # Compared against `spec.files`, NOT against a glob of the template. Both
  # sides of a glob-versus-glob comparison ignore .gitignore, so the check would
  # pass in a checkout while the installed gem was short files — which is the
  # failure it exists to catch.
  def test_every_template_file_is_in_spec_files
    gem_root = File.expand_path("../..", __dir__)
    spec = Dir.chdir(gem_root) { Gem::Specification.load(File.join(gem_root, "okf-pro.gemspec")) }
    template = OKF::Pro::Scaffold::ROOT.sub("#{gem_root}/", "")

    missing = %w[gem seed].flat_map do |half|
      OKF::Pro::Scaffold.entries(File.join(OKF::Pro::Scaffold::ROOT, half))
                        .map { |rel| "#{template}/#{half}/#{rel}" }
    end.reject { |path| spec.files.include?(path) }

    assert_empty missing, "these are in the template and not in the gem — an installed okf-pro " \
                          "would generate a tree missing them"
  end

  # A generated repository with no README is a repository nobody can land on.
  # It is seeded rather than gem-owned: the moment it exists it is the adopter's
  # description of their own project, and `upgrade` must never rewrite it.
  def test_a_generated_repository_has_a_readme
    in_empty do |dir|
      setup_into(dir)

      readme = File.join(dir, "README.md")
      assert File.file?(readme)
      assert_match(/core\.hooksPath \.githooks/, OKF::Pro.read_text(readme),
        "a clone arms its own commit door, and the README is where a person is told so")
    end
  end

  def test_the_readme_is_seeded_not_rewritten
    in_empty do |dir|
      setup_into(dir)
      File.write(File.join(dir, "README.md"), "my project\n")

      setup_into(dir, verb: "upgrade")

      assert_equal "my project\n", File.read(File.join(dir, "README.md"))
    end
  end

  def test_both_scripts_are_written_executable
    in_empty do |dir|
      setup_into(dir)

      OKF::Pro::Scaffold::EXECUTABLE.each do |rel|
        path = File.join(dir, rel)
        assert File.executable?(path),
          "#{rel} is not executable: git silently skips a non-executable hook, and the shell " \
          "reports 127, which the hook protocol reads as non-blocking"
      end
    end
  end

  # The template stores it as `gitignore`, without the dot, because as a real
  # dotfile in this gem's tree it would be a live gitignore governing its own
  # directory — silently deciding what `git ls-files` reports, and therefore
  # what ships.
  def test_the_gitignore_is_written_with_its_dot
    in_empty do |dir|
      setup_into(dir)

      assert File.file?(File.join(dir, ".gitignore"))
      refute File.exist?(File.join(dir, "gitignore"))
      assert_match(/\*\.okf-pro-new/, OKF::Pro.read_text(File.join(dir, ".gitignore")),
        "staged collisions are invisible to validate and lint inside .okf/, so they must be ignored")
    end
  end

  # A plain glob over this template returns ["CLAUDE.md"] and nothing else:
  # without FNM_DOTMATCH it does not match a leading dot, and the template is
  # almost entirely dotfiles.
  def test_the_enumeration_sees_the_dotfiles
    entries = OKF::Pro::Scaffold.entries(OKF::Pro::Scaffold::SEED_DIR)

    assert_includes entries, ".claude/settings.json"
    assert_includes entries, ".okf/board.md"
    refute_includes entries, "."
    refute_includes entries, ".."
  end

  # ── invariant 7 — the seeded README quotes the bundle, it does not describe it ──

  # The adopter's README shows `board.md` whole, because the fresh reader's
  # first unanswered question was what the file they live in actually looks
  # like. A quoted file is a copy, and a copy drifts: the board grew a section
  # and the README would keep showing five, which is worse than showing none —
  # a reader who diffs what they were promised against what they have stops
  # trusting the rest of the page. So the block is pinned to the shipped file
  # byte for byte rather than proof-read.
  def test_the_readme_quotes_the_shipped_board_verbatim
    root = OKF::Pro::Scaffold::SEED_DIR
    readme = OKF::Pro.read_text(File.join(root, "README.md"))
    board = OKF::Pro.read_text(File.join(root, ".okf", "board.md"))

    quoted = readme[/```markdown\n(---\ntype: Board\n.*?\n)```/m, 1]

    refute_nil quoted, "the seeded README no longer quotes board.md in a markdown block"
    assert_equal board.strip, quoted.strip
  end

  private

  # Dates outside a fenced block, an inline code span, or a link target.
  def dated_prose_lines(path)
    fenced = false
    OKF::Pro.read_text(path).each_line.map do |line|
      fenced = !fenced if line.start_with?("```")
      next if fenced

      bare = line.gsub(/`[^`]*`/, "")
      bare =~ /\d{4}-\d{2}-\d{2}/ ? line.strip : nil
    end.compact
  end
end

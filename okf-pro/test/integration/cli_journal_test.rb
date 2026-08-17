# frozen_string_literal: true

require "test_helper"

# `okf pro journal open` — today's day file, and its index line.
#
# It creates the file and indexes it, and stops. What goes in the day is
# judgment, and judgment stays the skill's — a verb that wrote the entry would
# be writing prose about a day it did not have.
class CLIJournalTest < OKF::Pro::TestCase
  TODAY = Date.today

  def index_of(b)
    OKF::Pro.read_text(File.join(b.bundle_path, "journal", "index.md"))
  end

  test "the day file is created and the index gains exactly one line" do
    with_bundle do |b|
      before = index_of(b)
      run = run_cli([ "journal", "open", b.path ])

      assert_equal OKF::Pro::PASS, run.status
      assert File.file?(File.join(b.bundle_path, "journal", "#{TODAY}.md"))
      added = index_of(b).lines.map(&:chomp) - before.lines.map(&:chomp)

      assert_equal [ "* [#{TODAY}](#{TODAY}.md) - the day's record." ], added
    end
  end

  test "the entry it writes is a conformant concept with the day as its title" do
    with_bundle do |b|
      run_cli([ "journal", "open", b.path ])
      entry = OKF::Pro.read_text(File.join(b.bundle_path, "journal", "#{TODAY}.md"))

      assert_match(/\A---\ntype: Journal Entry\n/, entry)
      assert_match(/title: "#{TODAY}"/, entry)
      assert_match(/^description: \S/, entry)
    end
  end

  test "the bundle validates, lints and audits clean afterwards" do
    with_bundle do |b|
      path = b.path
      assert_equal OKF::Pro::PASS, run_cli([ "journal", "open", path ]).status

      bundle = OKF::Bundle::Reader.read(b.bundle_path)

      assert OKF::Bundle::Validator.call(bundle).valid?
      assert_empty OKF::Bundle::Linter.call(bundle, today: Date.today, except: [ :stale ]).warnings
      assert_equal OKF::Pro::PASS, run_cli([ "audit", path ]).status
    end
  end

  # The seeded index says "Nothing recorded yet". Once a day is recorded that
  # is false, and leaving it would be a bundle asserting something untrue about
  # itself — so it comes out, as a declared removal the guard holds it to.
  test "the seeded empty-journal note is removed when the first day lands" do
    with_bundle do |b|
      path = b.path
      File.write(File.join(b.bundle_path, "journal", "index.md"),
        "# Journal\n\nOne entry per day.\n\nNothing recorded yet. The first entry is the first day this bundle is used,\n" \
        "dated by you, not by the template.\n")
      run_cli([ "journal", "open", path ])

      refute_match(/Nothing recorded yet/, index_of(b))
      assert_match(/\* \[#{TODAY}\]/, index_of(b))
    end
  end

  # An adopter who reworded it owns their words. A verb that pattern-matched
  # near-misses would be editing prose it did not write.
  test "a reworded note is left alone" do
    with_bundle do |b|
      path = b.path
      File.write(File.join(b.bundle_path, "journal", "index.md"),
        "# Journal\n\nNothing here yet, and that is fine.\n")
      run_cli([ "journal", "open", path ])

      assert_match(/Nothing here yet, and that is fine\./, index_of(b))
    end
  end

  test "a second day's line joins the list rather than starting a new block" do
    with_bundle do |b|
      path = b.path
      run_cli([ "journal", "open", path ])
      File.rename(File.join(b.bundle_path, "journal", "#{TODAY}.md"),
        File.join(b.bundle_path, "journal", "#{TODAY - 1}.md"))
      File.write(File.join(b.bundle_path, "journal", "index.md"),
        index_of(b).sub("[#{TODAY}](#{TODAY}.md)", "[#{TODAY - 1}](#{TODAY - 1}.md)"))
      run_cli([ "journal", "open", path ])

      assert_match(/\* \[#{TODAY - 1}\].*\n\* \[#{TODAY}\]/, index_of(b))
    end
  end

  # Idempotent, and it says which half it did not do: the file exists, so the
  # verb's whole job is done, and rewriting it would be regeneration.
  test "a day already open is reported and nothing is rewritten" do
    with_bundle do |b|
      path = b.path
      run_cli([ "journal", "open", path ])
      entry = File.join(b.bundle_path, "journal", "#{TODAY}.md")
      File.write(entry, "#{OKF::Pro.read_text(entry)}\nA sentence somebody wrote.\n")
      before = OKF::Pro.read_text(entry)
      index = index_of(b)
      run = run_cli([ "journal", "open", path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/already open/, run.out)
      assert_equal before, OKF::Pro.read_text(entry)
      assert_equal index, index_of(b)
    end
  end

  # The residue of a half-done pair — the day written, the index write lost —
  # is repaired by running the verb again, which is why the two conditions are
  # asked separately rather than off `File.exist?` alone. A state that needs a
  # maintainer to fix is a state nobody fixes.
  test "a day whose index line is missing gets it on the next run" do
    with_bundle do |b|
      path = b.path
      run_cli([ "journal", "open", path ])
      File.write(File.join(b.bundle_path, "journal", "index.md"),
        index_of(b).sub("* [#{TODAY}](#{TODAY}.md) - the day's record.\n", ""))
      run = run_cli([ "journal", "open", path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_match(/was already there and is now indexed/, run.out)
      assert_match(/\* \[#{TODAY}\]/, index_of(b))
    end
  end

  # The mirror of the test above, and the reason the two conditions are asked
  # separately: with the day file gone but the index line still there, adding a
  # second identical line would pass the conservation guard — the duplicate is
  # what the edit declared — and leave the index listing the day twice.
  test "a day whose file is gone but whose index line is there gains no second line" do
    with_bundle do |b|
      path = b.path
      run_cli([ "journal", "open", path ])
      File.delete(File.join(b.bundle_path, "journal", "#{TODAY}.md"))
      run = run_cli([ "journal", "open", path ])

      assert_equal OKF::Pro::PASS, run.status
      assert_equal 1, index_of(b).scan("(#{TODAY}.md)").size
    end
  end

  # The sibling policy, applied. `capture` will not create a board, because a
  # board written by a verb is a board nobody decided the shape of — and an
  # index regenerated from one entry line is the same thing, with the
  # `# Journal` heading and the seeded prose gone.
  test "a missing journal index is refused rather than regenerated from one line" do
    with_bundle do |b|
      path = b.path
      index = File.join(b.bundle_path, "journal", "index.md")
      FileUtils.rm(index)

      run = run_cli([ "journal", "open", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      refute File.exist?(index)
      refute File.exist?(File.join(b.bundle_path, "journal", "#{Date.today}.md"))
      assert_match(%r{journal/index\.md}, run.err)
    end
  end

  # The refusal points at `okf pro audit`, and a message naming a check has to
  # be a message that check answers — `a-comment-is-not-an-implementation`
  # applied to a refusal's own prose. (An empty journal has nothing to orphan
  # and nothing for the audit to say, which is why the sentence is conditional.)
  test "the day already written is the orphan the refusal names" do
    with_bundle do |b|
      day = Date.today
      b.write("journal/#{day}.md",
        "---\ntype: Journal Entry\ntitle: \"#{day}\"\ndescription: The day.\n---\n\n# #{day}\n\nSomething happened.\n")
      path = b.path
      FileUtils.rm(File.join(b.bundle_path, "journal", "index.md"))

      assert_equal OKF::Pro::BLOCK, run_cli([ "journal", "open", path ]).status
      run = run_cli([ "audit", path ])

      assert_equal OKF::Pro::FAIL, run.status
      assert_match(%r{journal/#{day}\.md.*orphan}, run.err)
    end
  end

  # The same question, for the file this verb appends to.
  test "a journal index symlinked out of the bundle is refused" do
    with_bundle(nested: true) do |b|
      root = b.path
      outside = File.join(root, "elsewhere.md")
      index = File.join(b.bundle_path, "journal", "index.md")
      FileUtils.cp(index, outside)
      File.unlink(index)
      File.symlink(outside, index)

      run = run_cli([ "journal", "open", root ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert File.symlink?(index), "the link was replaced by a real file"
      assert_match(/resolves outside/, run.err)
      refute File.exist?(File.join(b.bundle_path, "journal", "#{Date.today}.md"))
    end
  end

  # ── the subcommand ──────────────────────────────────────────────────────

  test "journal with no subcommand is a usage error" do
    run = run_cli([ "journal" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/takes one subcommand, `open`, and was given none/, run.err)
  end

  test "a flag where the subcommand goes is refused rather than read as one" do
    run = run_cli(%w[journal --json])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/looks like a flag, and this verb takes none/, run.err)
  end

  test "journal --help prints the usage" do
    run = run_cli(%w[journal --help])

    assert_equal OKF::Pro::PASS, run.status
    assert_match(/\AUsage: okf pro <command>/, run.out)
  end

  test "an unknown subcommand names what it was given" do
    run = run_cli(%w[journal close])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/was given 'close'/, run.err)
  end

  # ── the exits ───────────────────────────────────────────────────────────

  test "a bundle with no journal directory is exit 2" do
    with_bundle do |b|
      path = b.path
      FileUtils.rm_rf(File.join(b.bundle_path, "journal"))
      run = run_cli([ "journal", "open", path ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(%r{journal/ does not exist}, run.err)
    end
  end

  test "a directory holding no bundle is exit 2" do
    Dir.mktmpdir do |dir|
      run = run_cli([ "journal", "open", dir ])

      assert_equal OKF::Pro::BLOCK, run.status
      assert_match(/holds no OKF bundle/, run.err)
    end
  end

  test "a registry ref is refused by name" do
    run = run_cli([ "journal", "open", "@handbook" ])

    assert_equal OKF::Pro::BLOCK, run.status
    assert_match(/registry ref/, run.err)
  end

  test "a second directory is refused rather than ignored" do
    Dir.mktmpdir do |a|
      Dir.mktmpdir do |c|
        run = run_cli([ "journal", "open", a, c ])

        assert_equal OKF::Pro::BLOCK, run.status
        assert_match(/takes one directory/, run.err)
      end
    end
  end
end

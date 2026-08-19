# frozen_string_literal: true

require "test_helper"

# The door the other guards do not cover. guard-verified and journal-guard
# read a file_path and the text being added; a shell command has neither, so
# every trust rule in this repo used to step aside for a tool the agent
# already has — not a gate that refused, a gate that was never asked.
class ShellGuardTest < OKF::Pro::TestCase
  def bash_event(dir, command)
    event(tool_name: "Bash", cwd: dir, tool_input: { command: command })
  end

  def ask_for(dir, command)
    OKF::Pro::ShellGuard.check(bash_event(dir, command))
  end

  def test_a_heredoc_writing_a_concept_asks
    with_bundle do |b|
      dir = b.path
      result = ask_for(dir, "cat > .okf/reference/x.md <<'EOF'\nverified: me\nEOF")

      assert_kind_of Hash, result
      assert_match(/bypass the trust guards/, result["ask"])
    end
  end

  def test_an_in_place_edit_of_a_past_journal_day_asks
    with_bundle do |b|
      assert_kind_of Hash, ask_for(b.path, "sed -i '' 's/x/y/' .okf/journal/2026-01-01.md")
    end
  end

  def test_a_redirect_append_asks
    with_bundle do |b|
      assert_kind_of Hash, ask_for(b.path, "echo 'verified: me' >> .okf/reference/x.md")
    end
  end

  def test_moving_and_deleting_markdown_asks
    with_bundle do |b|
      dir = b.path

      assert_kind_of Hash, ask_for(dir, "mv .okf/reference/a.md .okf/reference/b.md")
      assert_kind_of Hash, ask_for(dir, "rm .okf/journal/2026-01-01.md")
    end
  end

  def test_an_inline_interpreter_write_asks
    with_bundle do |b|
      assert_kind_of Hash, ask_for(b.path, %(ruby -e 'File.write(".okf/reference/x.md", "verified: me")'))
    end
  end

  # A guard that fires on reads is a guard people switch off.
  def test_reading_the_bundle_is_not_a_write
    with_bundle do |b|
      dir = b.path

      assert_empty ask_for(dir, "grep -r 'verified' .okf")
      assert_empty ask_for(dir, "cat .okf/board.md")
      assert_empty ask_for(dir, "ls .okf/journal")
      assert_empty ask_for(dir, "git log --oneline .okf")
    end
  end

  def test_a_write_that_touches_no_markdown_is_not_this_guards_business
    with_bundle do |b|
      assert_empty ask_for(b.path, "echo hello > /tmp/scratch.txt")
    end
  end

  # Scoped like every other guard: no bundle here, nothing to protect.
  def test_outside_a_bundle_it_says_nothing
    Dir.mktmpdir do |dir|
      assert_empty ask_for(dir, "cat > notes.md <<'EOF'\nverified: me\nEOF")
    end
  end

  # Discarding stderr is not a write. This fired on every read-only command
  # that happened to mention a markdown file, which is the shape of noise that
  # trains an owner to approve without reading — the one outcome that makes
  # this guard worse than not having it.
  def test_discarding_stderr_is_not_a_write
    with_bundle do |b|
      dir = b.path

      assert_empty ask_for(dir, "grep -n 'verified' .okf/reference/x.md 2>/dev/null")
      assert_empty ask_for(dir, "cat .okf/board.md 2> /dev/null | head -40")
      assert_empty ask_for(dir, "ls .okf/journal >/dev/null 2>&1")
    end
  end

  # ...but a real write is still a write, whatever it does with its stderr.
  def test_a_write_that_also_discards_stderr_still_asks
    with_bundle do |b|
      dir = b.path

      assert_kind_of Hash, ask_for(dir, "cat > .okf/reference/x.md 2>/dev/null <<'EOF'\nverified: me\nEOF")
      assert_kind_of Hash, ask_for(dir, "echo 'verified: me' >> .okf/reference/x.md 2>/dev/null")
    end
  end

  # Markdown outside the bundle is somebody else's markdown. The guard used to
  # match `.md` anywhere on the filesystem, so reading a gem's CHANGELOG.md
  # from a repo that has a bundle in it asked the owner to approve a write.
  def test_markdown_outside_the_bundle_is_not_this_guards_business
    with_bundle(nested: true) do |b|
      dir = b.path

      assert_empty ask_for(dir, "cp /usr/local/gems/simplecov-1.0.3/CHANGELOG.md /tmp/x")
      assert_empty ask_for(dir, "rm /tmp/scratch/NOTES.md")
    end
  end

  # ...and markdown inside it still is, by either spelling.
  def test_markdown_inside_the_bundle_still_asks
    with_bundle(nested: true) do |b|
      dir = b.path

      assert_kind_of Hash, ask_for(dir, "rm #{b.bundle_path}/reference/x.md")
      assert_kind_of Hash, ask_for(dir, "mv notes.md elsewhere.md")
    end
  end

  # An ASCII arrow is not a redirection. `>` used to be matched anywhere in the
  # command, with nothing anchoring it to a position a redirection can occupy,
  # so `-->` and `=>` read as writes. The comment above MUTATORS claimed the
  # opposite for its whole life; the regex never implemented it.
  #
  # This bundle is the worst case for that. `-->` closes an HTML comment, and
  # the skill mandates balanced `<!-- ... -->` markers on the rules it keys; it
  # is also mermaid's edge. `=>` is in every quoted Ruby hash. So the payload
  # the guard exists to watch is the payload that made it misfire, and it
  # misfired on *reads* — the shape of noise that trains an owner to approve
  # without reading, which is the one outcome that makes this guard worse than
  # not having it.
  def test_ascii_arrows_are_not_redirections
    with_bundle do |b|
      dir = b.path

      assert_empty ask_for(dir, %(grep -rn "a --> b" .okf/))
      assert_empty ask_for(dir, %(grep -n "A --> B" .okf/index.md))
      assert_empty ask_for(dir, %(grep -rn "<!-- rule: okf-pro-closure-marker -->" .okf/))
      assert_empty ask_for(dir, %(grep -rn "status => open" .okf/board.md))
      assert_empty ask_for(dir, %(grep -rn "Board -> Journal" .okf/index.md))

      # The doubled arrows, whose trailing `>` is preceded by a `>` rather
      # than by the `-` that gives the arrow away.
      assert_empty ask_for(dir, %(grep -rn "A -->> B" .okf/index.md))
      assert_empty ask_for(dir, %(grep -rn "A ->> B" .okf/index.md))
      assert_empty ask_for(dir, %(grep -rn "A ==> B" .okf/index.md))
    end
  end

  # ...and the anchoring must not cost the real spellings. A redirection sits
  # after a boundary or a file descriptor, and every one of these is a write.
  def test_redirections_still_ask_in_every_spelling
    with_bundle do |b|
      dir = b.path

      assert_kind_of Hash, ask_for(dir, "echo x > .okf/reference/a.md")
      assert_kind_of Hash, ask_for(dir, "echo x >.okf/reference/a.md")
      assert_kind_of Hash, ask_for(dir, "echo x >> .okf/reference/a.md")
      assert_kind_of Hash, ask_for(dir, "cat .okf/board.md | tail -5 > .okf/reference/a.md")
      assert_kind_of Hash, ask_for(dir, "echo x 1> .okf/reference/a.md")
    end
  end

  def test_an_empty_command_is_not_a_write
    with_bundle do |b|
      assert_empty ask_for(b.path, "")
    end
  end

  # Ownership is a property of the SEGMENT that writes, not of the command.
  # `okf pro state && cat notes.md > .okf/board.md` mentions this gem and
  # hand-writes the board in the same breath — and asking the whole string let
  # the mention suppress the record, which is an under-count in a report whose
  # whole contract is that it does not lie about what it counted.
  def test_a_mention_of_okf_pro_does_not_excuse_a_hand_write_beside_it
    assert OKF::Pro::ShellGuard.own_write?("okf pro snapshot >> .okf/log.md")
    assert OKF::Pro::ShellGuard.own_write?("cd repo && okf  pro promote alpha")
    assert OKF::Pro::ShellGuard.own_write?("okf pro snapshot >> .okf/log.md && okf pro audit .")
    refute OKF::Pro::ShellGuard.own_write?("okf pro state && cat notes.md > .okf/board.md")
    refute OKF::Pro::ShellGuard.own_write?("cat notes.md > .okf/board.md && okf pro state")
    refute OKF::Pro::ShellGuard.own_write?("echo x >> .okf/board.md")
  end

  # A PIPELINE is one command, not two. `|` connects the stages of a single
  # invocation, so splitting on it put this gem's own redirect target in a
  # segment of its own and counted the prescribed "append the Snapshot line"
  # move as friction — the good path as evidence against itself, which is the
  # one thing the exclusion exists to prevent.
  def test_a_pipeline_is_one_command_and_its_target_is_not_a_separate_write
    assert OKF::Pro::ShellGuard.own_write?("okf pro snapshot | tee -a .okf/log.md")
    assert OKF::Pro::ShellGuard.own_write?("okf pro snapshot . | tee .okf/log.md")
    refute OKF::Pro::ShellGuard.own_write?("cat notes.md | tee .okf/board.md")
  end

  # A pipeline is one command, which is right — and it must not become a way to
  # launder a hand-write. `okf pro board | sed … > .okf/board.md` starts with
  # this gem and ends by regenerating the board, which is the Agent Drift shape
  # the design is named after. The prescribed move writes `log.md`, which no
  # verb covers; nothing prescribes piping into `board.md`.
  def test_a_pipeline_cannot_launder_a_write_to_the_board
    refute OKF::Pro::ShellGuard.own_write?("okf pro board | sed s/a/b/ > .okf/board.md")
    refute OKF::Pro::ShellGuard.own_write?("okf pro board > .okf/board.md")
    assert OKF::Pro::ShellGuard.own_write?("okf pro snapshot | tee -a .okf/log.md")
  end

  # A wrapper is not a different command. `bundle exec okf pro snapshot >>
  # .okf/log.md` is this repo's OWN invocation of the prescribed move, and it
  # was being recorded as friction — the good path as evidence against itself,
  # in the shape a contributor hits first.
  def test_a_wrapper_does_not_make_this_gems_own_move_someone_elses
    assert OKF::Pro::ShellGuard.own_write?("bundle exec okf pro snapshot >> .okf/log.md")
    assert OKF::Pro::ShellGuard.own_write?("env okf pro snapshot >> .okf/log.md")
    assert OKF::Pro::ShellGuard.own_write?("time okf pro snapshot >> .okf/log.md")
    refute OKF::Pro::ShellGuard.own_write?("bundle exec rake > .okf/board.md")
  end

  # An assignment prefix is part of the invocation, not a separate command —
  # and `$OKF_HOME` is a variable this ecosystem actually uses, so a prefixed
  # call is a shape that turns up. Anchoring without allowing it recorded the
  # gem's own prescribed move as friction.
  def test_an_environment_prefix_is_still_this_gems_own_invocation
    assert OKF::Pro::ShellGuard.own_write?("OKF_HOME=/tmp okf pro snapshot >> .okf/log.md")
    assert OKF::Pro::ShellGuard.own_write?("A=1 B=2 okf pro snapshot >> .okf/log.md")
    refute OKF::Pro::ShellGuard.own_write?("OKF_HOME=/tmp cat notes.md > .okf/board.md")
  end

  # The gem's name in a board line's TEXT is not an invocation of it, and board
  # lines routinely name its verbs. Matched anywhere in the segment, a hand-
  # append whose content mentioned `okf pro` was never recorded — the same
  # under-count, surviving in the commonest single-command shape.
  def test_the_gems_name_inside_content_is_not_an_invocation_of_it
    refute OKF::Pro::ShellGuard.own_write?('echo "- see okf pro docs" >> .okf/board.md')
    refute OKF::Pro::ShellGuard.own_write?(%q(printf '%s' "run okf pro capture" > .okf/board.md))
    assert OKF::Pro::ShellGuard.own_write?("okf pro capture \"a thing\"")
  end
end

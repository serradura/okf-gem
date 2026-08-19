# frozen_string_literal: true

require "fileutils"

module OKF
  module Pro
    # `okf pro setup` and `okf pro upgrade` — the generator, and the one
    # thing it may safely do twice.
    #
    # TWO CLASSES OF FILE, drawn by OWNERSHIP rather than by subject matter.
    #
    #   GEM-OWNED   the hook wrapper, the pre-commit hook, the workflow, the
    #               skill. These carry the fail-closed contract and the exit-code
    #               protocol; they must track the gem or a gate goes quietly
    #               wrong. `upgrade` rewrites them outright.
    #   SEEDED      CLAUDE.md, .gitignore, .claude/settings.json, and the whole
    #               of .okf/. Written once, and the adopter's from that moment.
    #
    # The split is not knowledge-versus-machinery, which is the obvious cut and
    # the wrong one: `CLAUDE.md` at a repo root is the adopter's own
    # agent-instruction file, `.gitignore` accumulates project entries from day
    # one, and `settings.json` is where they add hooks of their own. Classing
    # those as machinery makes `upgrade` destroy exactly the hand-merge that
    # adopting this thing asked them to perform.
    #
    # WHAT HAPPENS ON A COLLISION. A file the template wants and the adopter
    # already has is written beside it as `<path>.okf-pro-new`, with a merge
    # instruction printed. A stale one is refreshed rather than doubled — there
    # is never a `.okf-pro-new.okf-pro-new`.
    #
    # Except inside `.okf/`. A bundle that already exists is a bundle already
    # adopted, and eleven shadow files scattered through someone's knowledge is
    # not a merge prompt, it is litter — in a directory whose whole value is
    # that everything in it is deliberate. There, only missing files are added.
    #
    # ATOMICITY, STATED HONESTLY: each file is written to a temp path in its own
    # destination directory and renamed, so no half-written file ever exists.
    # A twenty-file sequence is not atomic as a *set*, and nothing here pretends
    # otherwise. The real safety is that `setup` is idempotent and re-runnable.
    module Scaffold
      ROOT = File.expand_path("template", __dir__)

      # `upgrade` rewrites these.
      GEM_DIR = File.join(ROOT, "gem")

      # `setup` writes these once; nothing ever rewrites them.
      SEED_DIR = File.join(ROOT, "seed")

      SUFFIX = ".okf-pro-new"

      # Stored without its dot and renamed on write. As a real dotfile in this
      # gem's tree it would be a live gitignore governing its own directory —
      # silently deciding what `git ls-files` reports, and therefore what ships.
      DOTFILES = { "gitignore" => ".gitignore" }.freeze

      # A wrapper without +x does not refuse: git silently skips a
      # non-executable hook, and the shell reports 127, which the hook protocol
      # reads as non-blocking. Both scripts are asserted executable on the
      # generated output, not merely here.
      EXECUTABLE = [ ".claude/hooks/run", ".githooks/pre-commit" ].freeze

      # The skill alone, for `okf pro skill <dest>`.
      SKILL_REL = ".claude/skills/okf-pro/SKILL.md"

      module_function

      def setup(dest, out:, err:)
        dest = File.expand_path(dest.to_s)

        refusal = flat_layout_refusal(dest)
        if refusal
          err.puts refusal
          return BLOCK
        end

        report(out, write_tree(GEM_DIR, dest) + write_tree(SEED_DIR, dest), dest, "setup")
        PASS
      end

      def upgrade(dest, out:, err:)
        dest = File.expand_path(dest.to_s)

        unless File.directory?(dest)
          err.puts "okf pro upgrade — #{dest} is not a directory."
          return BLOCK
        end

        # The gem-owned four are rewritten; the seeded ones are only completed.
        # An `upgrade` that overwrote a seeded file would take the adopter's own
        # CLAUDE.md with it, and an `upgrade` that staged every one of them would
        # bury the four files that actually changed under thirteen that did not.
        report(out, write_tree(GEM_DIR, dest, overwrite: true) + write_tree(SEED_DIR, dest), dest, "upgrade")
        PASS
      end

      # The destination tree is created — `.claude/skills/okf-pro` is the
      # natural place and `.claude/skills` often does not exist yet, so refusing
      # on a missing parent would refuse the common case to guard against a typo
      # that costs one `rm -r`.
      #
      # Overwritten rather than staged, unlike the seeded files: the skill is
      # gem-owned, and refreshing it is the entire reason this verb exists.
      def skill(dest, out:, err:)
        dest = File.expand_path(dest.to_s)

        if File.exist?(dest) && !File.directory?(dest)
          err.puts "okf pro skill — #{dest} is a file; the skill is a directory holding SKILL.md."
          return BLOCK
        end

        # Every file, not just the entry point. The skill was one file once, and
        # an installer that kept copying only `SKILL.md` would install something
        # that LOOKS installed — the entry point present, its index listing
        # guides, and every link in it dead. Nothing errors; the agent simply
        # cannot follow its own instructions.
        source = File.join(GEM_DIR, File.dirname(SKILL_REL))
        results = entries(source).map do |rel|
          copy(File.join(source, rel), File.join(dest, rel), overwrite: true)
        end

        report(out, results, dest, "skill")
        PASS
      end

      # Every path a template directory holds, relative, dotfiles included.
      #
      # A plain glob returns `["CLAUDE.md"]` and nothing else here: without
      # FNM_DOTMATCH it does not match a leading dot, and this template is
      # almost entirely dotfiles. `.` and `..` are rejected explicitly, which
      # the flag makes necessary.
      def entries(template)
        Dir.glob(File.join(template, "**", "*"), File::FNM_DOTMATCH)
           .reject { |path| [ ".", ".." ].include?(File.basename(path)) }
           .select { |path| File.file?(path) }
           .map { |path| path[(template.size + 1)..-1] }
           .sort
      end

      # Where a template-relative path lands in the destination.
      def target_rel(rel)
        parts = rel.split("/")
        parts[-1] = DOTFILES.fetch(parts.last, parts.last)
        parts.join("/")
      end

      def write_tree(template, dest, overwrite: false)
        entries(template).map do |rel|
          copy(File.join(template, rel), File.join(dest, target_rel(rel)),
            overwrite: overwrite, rel: target_rel(rel))
        end
      end

      # One file. Returns [ :written | :staged | :kept, path ] — the verb's
      # report is built from these rather than printed here, so that the whole
      # decision about what happened lives in one place.
      #
      # `rel` is the path *within the destination*, and it is what the `.okf/`
      # exemption is asked about. Asking the absolute path would put every file
      # of a repository that happens to live under a directory named `.okf` on
      # the exempt side, which is a plausible enough path (`~/.okf/notes`) to be
      # worth not getting wrong.
      def copy(source, target, overwrite: false, rel: nil)
        unless File.exist?(target)
          write_atomically(target, File.binread(source), executable?(target))
          return [ :written, target ]
        end
        return [ :written, target ] if overwrite && write_atomically(target, File.binread(source), executable?(target))
        return [ :kept, target ] if inside_bundle?(rel) || File.binread(target) == File.binread(source)

        staged = "#{target}#{SUFFIX}"
        write_atomically(staged, File.binread(source), executable?(target))
        [ :staged, staged ]
      end

      # The `.okf/` exemption: a bundle that exists is a bundle already adopted,
      # and eleven shadow files through someone's knowledge is litter, not a
      # merge prompt. `rel` is nil for the single-file `skill` verb, which is
      # gem-owned and overwrites before reaching here.
      def inside_bundle?(rel)
        rel.to_s.split("/").first == BundleRoot::DIR
      end

      def executable?(target)
        EXECUTABLE.any? { |rel| target.end_with?("/#{rel}") }
      end

      def write_atomically(target, content, executable)
        FileUtils.mkdir_p(File.dirname(target))
        tmp = "#{target}.okf-pro-tmp-#{Process.pid}"
        File.binwrite(tmp, content)
        File.chmod(executable ? 0o755 : 0o644, tmp)
        File.rename(tmp, target)
        true
      ensure
        File.unlink(tmp) if tmp && File.exist?(tmp)
      end

      # `setup` into a bundle whose root IS the repository root.
      #
      # Writing `.okf/index.md` beside it collides with nothing, so the naive
      # generator succeeds and leaves two bundle roots in one directory — the
      # exact state `Audit.ambiguous_layout` exists to report, where the three
      # doors disagree until one of the two is retired. Refusing is the only
      # honest answer: the migration is the adopter's to make, and it is one
      # `git mv` they can see.
      # Asked with `root_kind`, the same predicate `Audit.ambiguous_layout` asks,
      # because this refusal cites that finding by name. It asked `bundle?` —
      # `index.md` alone — while the finding needs index.md PLUS board.md or
      # log.md, or an `okf_version` in the frontmatter. So every Jekyll section,
      # Hugo directory and repo with an `index.md` README was refused, and told
      # to `git mv` files that have nothing to do with OKF, for an ambiguity the
      # audit would never have reported. A refusal that names a finding has to
      # be answering the question that finding asks.
      def flat_layout_refusal(dest)
        return nil unless File.directory?(dest)
        return nil if BundleRoot.bundle?(File.join(dest, BundleRoot::DIR))
        return nil if BundleRoot.root_kind(dest).nil?

        "okf pro setup — #{dest} is already an OKF bundle at its own root, and this scaffold " \
          "puts the bundle under #{BundleRoot::DIR}/. Writing one here would leave two bundle roots " \
          "in one directory, which the audit reports as an ambiguous layout and the three doors " \
          "then disagree about. Move it first:\n  " \
          "mkdir #{BundleRoot::DIR} && git mv index.md log.md <your dirs> #{BundleRoot::DIR}/\n" \
          "then run setup again."
      end

      def report(out, results, dest, verb)
        written = results.select { |kind, _| kind == :written }
        staged = results.select { |kind, _| kind == :staged }

        out.puts "okf pro #{verb} — #{dest}"
        out.puts "  #{written.size} written, #{staged.size} staged, #{results.size - written.size - staged.size} left alone"
        return if staged.empty?

        out.puts "  These already existed and are yours, so the template's version is beside them:"
        staged.each { |entry| out.puts "    #{entry.last}" }
        out.puts "  Merge what you want from each, then delete it. #{ignore_note(dest)}"
      end

      # The last line of that report is a claim about the reader's own tree, so
      # it is read from the tree rather than assumed.
      #
      # It was assumed, and it was false in exactly the case that matters: when
      # `.gitignore` is itself the collision, the adopter's own file is what
      # stays on disk and the template's — the one carrying `*#{SUFFIX}` — is
      # what got staged beside it. Telling them it is already ignored is how the
      # staged copies end up committed with nothing ever saying so, which is the
      # failure the seeded `.gitignore` comment exists to name.
      def ignore_note(dest)
        gitignore = File.join(dest, ".gitignore")
        ignored = File.file?(gitignore) && Pro.read_text(gitignore).include?("*#{SUFFIX}")
        return "`.gitignore` already ignores *#{SUFFIX}." if ignored

        "Add `*#{SUFFIX}` to `.gitignore` first, or they get committed."
      end
    end
  end
end

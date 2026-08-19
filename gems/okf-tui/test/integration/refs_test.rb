# frozen_string_literal: true

require "test_helper"
require "okf/tui/cli"

module Integration
  # Registry refs, and which registry they resolve against.
  #
  # `okf help` advertises `tui [DIR|@slug…]`, so every ref form okf's other
  # multi-bundle verb accepts has to work here — and mean the same thing, because
  # the grammar is inherited rather than re-implemented (see OKF::TUI::Refs).
  class RefsTest < OKF::TUI::TestCase
    # ── the seam ─────────────────────────────────────────────────────────────

    # Refs subclasses OKF::CLI::Command for a *private* helper, which is okf's
    # internal. That is a deliberate trade — one copy of the ref grammar, at the
    # cost of a coupling — and this is the check that makes the cost visible: if
    # okf renames or moves the resolver, this fails by name, rather than every
    # @slug silently going back to reading as "not a directory".
    test "okf still resolves refs where Refs reaches for it" do
      assert_includes OKF::CLI::Command.private_instance_methods, :resolve_ref_expanding,
        "okf moved its ref resolver — OKF::TUI::Refs has to follow it, not route around it"
      assert_includes OKF::CLI::Command.private_instance_methods, :ref_slugs,
        "okf moved the resolved-slug map — Refs#slugs reads it"
    end

    test "Refs is a resolver, never a verb" do
      # It inherits Command, so the only thing keeping it from answering `okf
      # tui-refs` is that nothing registers it. Worth asserting: a stray
      # `register` would put an internal helper on okf's public map.
      refute_includes OKF::CLI.commands.map(&:id), OKF::TUI::Refs.id
      assert_nil OKF::CLI.lookup("tui-refs")
    end

    # ── the ref forms ────────────────────────────────────────────────────────

    test "an @slug names a registered bundle" do
      with_registry(:conformant, :minimal) do
        assert_equal %w[minimal], slugs_for("@minimal")
      end
    end

    test "a bare @ is the registry default" do
      with_registry(:conformant, :minimal) do
        # First registered is the default, which is okf's rule, not ours.
        assert_equal %w[conformant], slugs_for("@")
      end
    end

    test "an @group fans out to its members" do
      with_registry(:conformant, :minimal, :nested) do |_home, registry|
        registry.set_group("pair", %w[@minimal @nested])

        assert_equal %w[minimal nested], slugs_for("@pair")
      end
    end

    test "a group's members keep the slugs they are registered under" do
      # The regression this exists for. Every bundle that follows the `.okf`
      # convention has the same basename, so slugging from the directory would
      # name a two-member group @okf and @okf-2 — discarding both registered
      # names. okf fixed the same bug in its hub; the TUI reads the same map.
      with_registry(:conformant, :minimal) do |_home, registry|
        registry.rename("conformant", "sales")
        registry.rename("minimal", "notes")
        registry.set_group("both", %w[@sales @notes])

        assert_equal %w[sales notes], slugs_for("@both"),
          "a ref-built session should carry the registered names, not dir basenames"
      end
    end

    test "directories and refs mix in one argv" do
      with_registry(:minimal) do
        dirs, slug_map = resolve("@minimal", fixture("nested"))
        workspace = OKF::TUI::Workspace.new(dirs: dirs, ref_slugs: slug_map)

        assert_equal %w[minimal nested], workspace.entries.map(&:slug)
        assert workspace.entry("minimal").registered?, "the @ref came from the registry"
        refute workspace.entry("nested").registered?, "the directory did not"
      end
    end

    test "@all is refused by name, because it is search's alone" do
      with_registry(:conformant) do
        status, _out, err = run_cli("@all")

        assert_equal OKF::TUI::CLI::USAGE_ERROR, status
        assert_includes err, "@all"
        assert_includes err, "okf search"
      end
    end

    test "an unknown slug is a usage error naming the registry file" do
      with_registry(:conformant) do
        status, _out, err = run_cli("@nope")

        assert_equal OKF::TUI::CLI::USAGE_ERROR, status
        assert_includes err, "not a registered bundle: @nope"
        assert_includes err, "registry.json"
      end
    end

    test "both doors accept an @slug, and agree" do
      with_registry(:conformant) do
        through_okf = run_okf("tui", "@conformant")
        direct = run_okf_tui("@conformant")

        assert_equal direct[0], through_okf[0], "same exit code"
        assert_equal direct[2], through_okf[2], "and the same message — one CLI, two doors"
        # Both reached the terminal gate, which is past resolution: the ref
        # resolved rather than being rejected as a directory that is not one.
        assert_includes direct[2], "needs an interactive terminal"
        refute_includes direct[2], "not a directory"
      end
    end

    # ── which registry ───────────────────────────────────────────────────────

    test "a project-local registry is the one a ref resolves against" do
      with_local_registry(:nested) do |project, _local, global|
        global.add(fixture(:conformant))

        Dir.chdir(project) do
          dirs, slug_map = resolve("@nested")
          workspace = OKF::TUI::Workspace.new(dirs: dirs, ref_slugs: slug_map)

          assert_equal %w[nested], workspace.entries.map(&:slug),
            "@nested is only in the local registry — resolving it proves discovery ran"
        end
      end
    end

    test "a registry-backed session reads the discovered local registry" do
      with_local_registry(:nested) do |project, local, global|
        global.add(fixture(:conformant))

        workspace = OKF::TUI::Workspace.new(cwd: project)

        assert_equal %w[nested], workspace.entries.map(&:slug),
          "the local registry's bundles, not the global one's"
        assert_equal local.path, workspace.registry_path,
          "and the header should name the file actually being read"
      end
    end

    test "the CLI opts into discovery, and names the local file it found" do
      # An empty local registry is the assertable signal: the "nothing to show"
      # message names the registry it read, so this proves the CLI passed a cwd
      # rather than merely that Workspace can accept one.
      with_local_registry do |project, local, global|
        global.add(fixture(:conformant))

        Dir.chdir(project) do
          status, _out, err = run_cli

          assert_equal OKF::TUI::CLI::USAGE_ERROR, status
          assert_includes err, local.path,
            "the TUI should report the registry every other okf verb here reads"
          refute_includes err, "home", "and not the global one it ignored"
        end
      end
    end

    test "an embedding app with no cwd stays on the global registry" do
      # okf draws this line itself — only its CLI passes a cwd. A default of
      # Dir.pwd here would make an embedded workspace depend on the directory its
      # host process happens to sit in.
      with_local_registry(:nested) do |project, _local, global|
        global.add(fixture(:conformant))

        Dir.chdir(project) do
          workspace = OKF::TUI::Workspace.new

          assert_equal %w[conformant], workspace.entries.map(&:slug)
        end
      end
    end

    test "OKF_NO_DISCOVERY forces the global registry" do
      with_local_registry(:nested) do |project, _local, global|
        global.add(fixture(:conformant))

        # begin/ensure, not a bare `ensure` in the block: that spelling is Ruby
        # 2.6 syntax and this suite runs on 2.4 (see the contract in AGENTS.md).
        begin
          was = ENV.fetch("OKF_NO_DISCOVERY", nil)
          ENV["OKF_NO_DISCOVERY"] = "1"

          workspace = OKF::TUI::Workspace.new(cwd: project)

          assert_equal %w[conformant], workspace.entries.map(&:slug),
            "the documented escape hatch has to work here too"
        ensure
          was.nil? ? ENV.delete("OKF_NO_DISCOVERY") : ENV["OKF_NO_DISCOVERY"] = was
        end
      end
    end

    private

    def resolve(*argv)
      resolver = OKF::TUI::Refs.new(out: StringIO.new, err: StringIO.new)
      [ resolver.resolve(argv), resolver.slugs ]
    end

    def slugs_for(*argv)
      dirs, slug_map = resolve(*argv)
      refute_nil dirs, "the ref should have resolved"
      OKF::TUI::Workspace.new(dirs: dirs, ref_slugs: slug_map).entries.map(&:slug)
    end

    def run_cli(*argv)
      out = StringIO.new
      err = StringIO.new
      status = OKF::TUI::CLI.run(argv, out: out, err: err, input: StringIO.new)
      [ status, out.string, err.string ]
    end

    def run_okf(*argv)
      out = StringIO.new
      err = StringIO.new
      status = OKF::CLI.start(argv, out: out, err: err, input: StringIO.new)
      [ status, out.string, err.string ]
    end

    def run_okf_tui(*argv)
      out = StringIO.new
      err = StringIO.new
      status = OKF::TUI::CLI.run(argv, out: out, err: err, input: StringIO.new)
      [ status, out.string, err.string ]
    end
  end
end

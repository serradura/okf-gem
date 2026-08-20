# frozen_string_literal: true

require_relative "../cli_integration_case"

# `okf registry init` end-to-end — create a project-local .okf-registry.json in
# the current directory. Once it exists, discovery finds it and every registry op
# targets it instead of the global $OKF_HOME one (see cli_registry_discovery_test).
# init itself only writes the file; populating it is `registry set`'s job.
#
# The base class chdirs every test into a scratch cwd with no local registry above
# it, so `init` writes there and never touches the repo (see the setup comment).
module ByRegistry
  class CLIRegistryInitTest < CLIIntegrationCase
    LOCAL = ".okf-registry.json"

    test "init creates an empty local registry in the current directory" do
      result = okf("registry", "init")

      assert_equal 0, result.status
      assert_equal "initialized ./#{LOCAL}\n", result.out
      created = File.join(Dir.pwd, LOCAL)
      assert_path_exists created, "the file lands in cwd, which the harness pins to a scratch dir"
      assert_equal({ "bundles" => [], "groups" => [] }, JSON.parse(File.read(created)),
        "a fresh local registry is empty, not seeded with cwd")
    end

    test "init refuses to clobber a populated local registry (exit 2)" do
      planted = File.join(Dir.pwd, LOCAL)
      populated = JSON.pretty_generate("bundles" => [ { "slug" => "keep", "path" => fixture("conformant"),
                                                        "title" => "keep" } ], "groups" => []) + "\n"
      File.write(planted, populated)

      result = okf("registry", "init")

      assert_equal 2, result.status
      assert_match(/^error: already initialized: \.\/#{Regexp.escape(LOCAL)}$/, result.err)
      assert_equal populated, File.read(planted), "a refused init leaves the existing registry byte-for-byte intact"
    end

    test "init in a subdirectory of a local registry still creates one, noting the parent" do
      parent = File.join(@out_dir, "project")
      child = File.join(parent, "sub")
      FileUtils.mkdir_p(child)
      File.write(File.join(parent, LOCAL), JSON.generate("bundles" => [], "groups" => []))

      result = in_dir(child) { okf("registry", "init") }

      assert_equal 0, result.status
      assert_path_exists File.join(child, LOCAL), "a nested init creates the nearer registry"
      # Dir.pwd canonicalizes symlinks (on macOS /var → /private/var), so the note
      # names the resolved path — realpath the expectation to match it.
      shadowed = File.realpath(File.join(parent, LOCAL))
      assert_match(/^note: a parent registry at #{Regexp.escape(shadowed)} — the nearest one wins$/,
        result.err, "the note points at the file the new one now shadows")
    end

    test "a stray positional is a usage error (exit 2)" do
      result = okf("registry", "init", "here")

      assert_equal 2, result.status
      assert_match(/unexpected argument 'here'/, result.err)
      refute_path_exists File.join(Dir.pwd, LOCAL), "a rejected invocation writes nothing"
    end

    test "an unknown flag is a usage error (exit 2), reported not raised" do
      result = okf("registry", "init", "--bogus")

      assert_equal 2, result.status
      assert_match(/invalid option: --bogus/, result.err)
      refute_match(/\.rb:\d+/, result.err, "a bad flag is a message, never a backtrace")
      refute_path_exists File.join(Dir.pwd, LOCAL), "a rejected invocation writes nothing"
    end

    test "init --help prints usage and writes no file" do
      result = okf("registry", "init", "--help")

      assert_equal 0, result.status
      assert_match(/Usage: okf registry init/, result.out)
      refute_path_exists File.join(Dir.pwd, LOCAL), "help is not a side effect"
    end

    test "an unwritable directory is a usage error naming it, not a backtrace" do
      skip_unless_permissions_bite
      readonly = File.join(@out_dir, "readonly")
      FileUtils.mkdir_p(readonly)
      File.chmod(0o500, readonly)

      begin
        result = in_dir(readonly) { okf("registry", "init") }

        assert_equal 2, result.status
        refute_match(/\.rb:\d+/, result.err, "an unwritable cwd is a message, never a backtrace")
        assert_match(/^error: .*ermission denied/, result.err)
      ensure
        File.chmod(0o700, readonly)
      end
    end
  end
end

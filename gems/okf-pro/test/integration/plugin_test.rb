# frozen_string_literal: true

require "test_helper"

# The seam itself, driven the way a user reaches it: okf's own executable, with
# this gem on the load path, and nothing else arranged.
#
# Installing the gem is the whole installation — there is no configuration step,
# and nothing in okf names this gem. What that buys is discoverability: somebody
# who installed okf-pro finds it in `okf help` without having to know a second
# command exists. It is also the only place the *registration* is proven; every
# other test in this suite calls `Pro::CLI.run` directly and would stay green
# with the plugin file deleted.
class PluginTest < OKF::Pro::TestCase
  Result = Struct.new(:status, :out, :err)

  def okf(*argv, env: {}, stdin: "")
    Dir.mktmpdir("plugin-") do |dir|
      File.write(File.join(dir, "in"), stdin)
      out = File.join(dir, "out")
      err = File.join(dir, "err")
      command = [ RbConfig.ruby, "-I#{BundleFixture::OKF_ROOT}/lib", "-I#{BundleFixture::PRO_LIB}",
                  File.join(BundleFixture::OKF_ROOT, "exe", "okf"), *argv ]
      system(cleared_bundler_env.merge(env), *command, in: File.join(dir, "in"), out: out, err: err)
      Result.new($?.exitstatus, read_stream(out), read_stream(err))
    end
  end

  # One line in the map. An extension that printed its whole surface here would
  # dwarf the built-ins it sits under, and this gem has eight subcommands.
  #
  # What is asserted is only what THIS gem controls: that it contributes a single
  # row, and that the row names the umbrella verb. Whether the heading then points
  # the reader at `okf <verb> --help` is the kernel's to decide and the kernel's
  # to test — asserting it here would couple this suite to an okf newer than the
  # one the gemspec requires, and pass only against a checkout.
  def test_okf_help_lists_pro_as_a_single_line
    result = okf("help")

    assert_equal 0, result.status
    extensions = result.out.split("installed extensions").last.to_s

    assert_equal 1, extensions.scan(/^\s+pro\b/).size, "the map is a map, not a manual"
    assert_match(/^\s+pro\s+<command>/, extensions)
  end

  def test_the_verb_dispatches_through_okf
    with_bundle do |b|
      result = okf("pro", "audit", b.path)

      assert_equal 0, result.status
      assert_match(/okf pro audit — clean\./, result.out)
    end
  end

  # A findings exit is 1 through the real binary too — `okf/exe/okf` is
  # `exit OKF::CLI.start(ARGV)`, so the status a command returns is the process's.
  def test_a_findings_exit_survives_the_dispatch
    with_bundle do |b|
      dir = b.path # forces the fixture to write itself before we break it
      File.write(File.join(b.dir, "board.md"),
        "---\ntype: Board\ntitle: Board\ndescription: A board with no sections.\n---\n\n# Board\n")

      result = okf("pro", "audit", dir)

      assert_equal 1, result.status
      assert_match(/finding\(s\)/, result.err)
    end
  end

  # `hook` is the door with the different protocol, and the marker is what the
  # wrapper reads. Both have to survive the trip through okf's dispatch.
  def test_a_hook_check_identifies_itself_and_returns_the_protocols_code
    with_bundle do |b|
      b.raw("glossary/broken.md", "# Broken\n\nNo frontmatter, so no type.\n")
      event = JSON.generate("tool_name" => "Edit", "cwd" => b.path,
        "tool_input" => { "file_path" => File.join(b.path, "glossary/broken.md") })

      result = okf("pro", "hook", "check-okf", stdin: event)

      assert_equal 2, result.status
      assert_match(/\Aokf-pro-enforcer v1\n/, result.err)
      assert_match(/okf validate failed/, result.err)
    end
  end

  # The whitelist, through the real dispatch: `Pro::CLI.run` reads the CI verbs
  # off the same argv element, so without it a settings.json typo would install a
  # gate that reports clean without reading the event.
  def test_hook_refuses_a_ci_verb
    result = okf("pro", "hook", "audit")

    assert_equal 2, result.status
    assert_match(/ENFORCEMENT MISCONFIGURED/, result.err)
    assert_empty result.out
  end

  # The registration must not name this gem from okf's side, and okf's own suite
  # greps for that. This is the other half: the seam is a convention, so the verb
  # has to appear with nothing but the load path arranged.
  def test_nothing_but_the_load_path_is_required
    result = okf("pro", "snapshot", "--help")

    refute_equal 127, result.status, "the verb must exist with no configuration at all"
  end

  # `okf pro hook --help` must NOT be help, and this is the one place worth
  # spelling out. The hook door's exit 0 means "the gate ran and found nothing",
  # so a settings.json that reached a help branch and got 0 would be a gate
  # switched off in silence — the failure this gem exists to make impossible.
  # It refuses, and says where help actually lives.
  def test_hook_help_refuses_rather_than_passing
    result = okf("pro", "hook", "--help")

    assert_equal 2, result.status
    assert_match(/ENFORCEMENT MISCONFIGURED/, result.err)
    assert_match(/okf pro --help/, result.err)
    assert_empty result.out
  end

  def test_pro_help_prints_the_usage_and_exits_zero
    result = okf("pro", "--help")

    assert_equal 0, result.status
    assert_match(/\AUsage: okf pro <command>/, result.out)
  end

  def test_pro_with_no_command_prints_the_usage_and_exits_two
    result = okf("pro")

    assert_equal 2, result.status
    assert_match(/\AUsage: okf pro <command>/, result.err)
  end
end

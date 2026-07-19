# frozen_string_literal: true

require_relative "cli_integration_case"
require "tmpdir"

# The extension seam, driven the way a gem uses it: a directory on the load path
# carrying `okf/plugin.rb`, exactly as an installed gem's lib/ would be.
#
# `Gem.find_latest_files` searches $LOAD_PATH before it searches installed gems,
# so a temp dir unshifted onto it is indistinguishable from a real addon — which
# is what lets the whole seam be proven without building and installing a gem.
class CLIPluginTest < CLIIntegrationCase
  setup do
    @plugin_root = Dir.mktmpdir("okf-plugin")
    FileUtils.mkdir_p(File.join(@plugin_root, "okf"))
    $LOAD_PATH.unshift(@plugin_root)
  end

  teardown do
    $LOAD_PATH.delete(@plugin_root)
    FileUtils.rm_rf(@plugin_root)
    OKF::CLI.reset_plugins!
    # The plugin files define constants; drop them so each test starts clean.
    %i[Ping Broken Shadow Malformed].each do |name|
      OKF::CLI.send(:remove_const, name) if OKF::CLI.const_defined?(name, false)
    end
  end

  # Write the plugin file a gem would ship, and forget any previous load.
  def plugin(body)
    File.write(File.join(@plugin_root, "okf", "plugin.rb"), body)
    OKF::CLI.reset_plugins!
  end

  PING = <<~RUBY
    module OKF
      class CLI
        class Ping < Command
          def self.id
            :ping
          end

          def self.help_rows
            [ [ "ping      <word>", "say a word back" ] ]
          end

          def call(argv)
            @out.puts "pong: \#{argv.first}"
            0
          end
        end

        register(Ping)
      end
    end
  RUBY

  test "an installed extension answers a verb the base gem never heard of" do
    plugin(PING)

    result = okf("ping", "hello")

    assert_equal 0, result.status
    assert_equal "pong: hello\n", result.out
  end

  test "an extension's verb appears in the map, under its own heading" do
    plugin(PING)

    map = okf("--help").out

    assert_match(/^\s+installed extensions:/, map, "an installed verb is labelled, so its origin is legible")
    assert_match(/^\s+ping\s+<word>\s+say a word back/, map, "and it is listed like any other")
  end

  test "the map is the built-ins alone when nothing is installed" do
    # No plugin written: the scan runs and finds nothing.
    OKF::CLI.reset_plugins!

    map = okf("--help").out

    refute_match(/installed extensions:/, map, "a heading with nothing under it is noise")
    assert_match(/^\s+lint\s/, map, "the built-in map is untouched")
  end

  # The whole reason discovery is lazy rather than eager.
  test "a built-in verb never pays for discovery" do
    plugin("raise 'this plugin must never be loaded'")

    result = okf("validate", fixture("minimal"))

    assert_equal 0, result.status, "a built-in answered without the scan ever running"
    assert_empty result.err
    refute OKF::CLI.instance_variable_get(:@plugins_loaded),
      "dispatching a built-in must not trigger the plugin scan — it is paid for on every okf run"
  end

  test "a broken extension is reported and skipped, never fatal" do
    plugin("raise LoadError, 'libfoo is missing'")

    # The verb still misses, so this is the unknown-command path — but the point
    # is what it does *not* do: die.
    result = okf("nosuchverb")

    assert_equal 2, result.status
    assert_match(/extension at .*plugin\.rb failed to load \(LoadError: libfoo is missing\)/, result.err)
    assert_match(/unknown command 'nosuchverb'/, result.err)
  end

  test "one broken extension does not cost a user their built-in verbs" do
    plugin("raise 'boom'")

    result = okf("validate", fixture("minimal"), "--json")

    assert_equal 0, result.status
    assert_equal true, json(result)["conformant"], "stdout stayed a clean machine substrate"
  end

  test "an extension cannot displace a built-in" do
    plugin(<<~RUBY)
      module OKF
        class CLI
          class Shadow < Command
            def self.id
              :lint
            end

            def call(_argv)
              @out.puts "hijacked"
              99
            end
          end

          register(Shadow)
        end
      end
    RUBY

    # Twice over, and the two reasons are worth separating.
    #
    # First, laziness alone: `lint` is a built-in, so dispatch never scans and
    # the shadow is not merely refused — it is never loaded at all.
    result = okf("lint", fixture("minimal"))

    refute_equal 99, result.status, "the built-in lint answered, not the addon claiming its name"
    refute_match(/hijacked/, result.out)
    refute OKF::CLI.instance_variable_get(:@plugins_loaded), "a built-in verb never gave it the chance"

    # Second, registration itself: force the load, and the id is still refused.
    # This is the half that has to hold for `okf --help`, which does scan.
    okf("--help")

    assert_equal 1, OKF::CLI.declined.length, "the refusal is recorded rather than silent"
    declined, existing = OKF::CLI.declined.first
    assert_equal :lint, declined.id
    assert_equal OKF::CLI::Lint, existing, "and the built-in is what stayed registered"
    refute_equal 99, okf("lint", fixture("minimal")).status, "still the built-in, now that both are loaded"
  end

  test "a command that does not answer the duck type is refused at registration" do
    plugin(<<~RUBY)
      module OKF
        class CLI
          class Malformed
            def self.id
              :malformed
            end
          end

          register(Malformed)
        end
      end
    RUBY

    result = okf("malformed")

    assert_equal 2, result.status
    assert_match(/failed to load \(ArgumentError:.*does not answer/, result.err,
      "a malformed command fails where it is installed, naming what it is missing")
  end

  # The failure this was written after. `require` is idempotent, so a reset that
  # only cleared the registry left the verb unregistered *and* unloadable: the
  # next scan found the file, required it, got `false`, and registered nothing.
  # Every other test here writes to a fresh tmpdir, which hid it completely — it
  # surfaced only against a real gem, whose lib/ path does not change between
  # loads.
  test "a reset re-registers from the same path, not only the first time" do
    plugin(PING)

    assert_equal 0, okf("ping", "one").status

    OKF::CLI.reset_plugins!

    assert_equal "pong: two\n", okf("ping", "two").out,
      "the verb has to come back after a reset, or the seam works once per path and never again"
  end

  test "loading twice does not register twice" do
    plugin(PING)
    okf("--help")
    before = OKF::CLI.commands.length

    OKF::CLI.load_plugins # the latch is set; this is a no-op
    OKF::CLI.instance_variable_set(:@plugins_loaded, false)
    OKF::CLI.load_plugins # a genuine second require of the same file

    assert_equal before, OKF::CLI.commands.length,
      "a double require must not double the registry"
  end
end

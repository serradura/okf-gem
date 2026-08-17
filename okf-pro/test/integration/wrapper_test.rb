# frozen_string_literal: true

require "test_helper"

# The agent-door wrapper, tested as the shell script it is — and the centre of
# gravity of this whole suite. Every bug this layer has produced was a gate that
# *passed* when it could not do its job, which is the one failure mode nothing
# downstream can see: an unchecked edit and a clean edit look identical from the
# protocol's side.
#
# So each drill below names a way the seam can be broken and asserts the wrapper
# refuses. They are drills rather than unit tests on purpose: the script is run
# as a subprocess, with a real PATH, a real event on stdin, and its real exit
# status read — because that is the only arrangement in which "the hook protocol
# reads this as non-blocking" is a statement about anything.
class WrapperTest < OKF::Pro::TestCase
  TEMPLATE = File.expand_path("../../lib/okf/pro/template/gem/.claude/hooks/run", __dir__)

  OKF_ROOT = BundleFixture::OKF_ROOT
  PRO_LIB = BundleFixture::PRO_LIB

  Result = Struct.new(:status, :out, :err)

  # Runs the wrapper with the event on stdin and both streams captured. Reading
  # them matters as much as the status: a drill that only checked the code would
  # pass on a wrapper that refused for the wrong reason.
  def drill(env, *args, event: "{}")
    Dir.mktmpdir("drill-") do |dir|
      File.write(File.join(dir, "event"), event)
      out = File.join(dir, "out")
      err = File.join(dir, "err")
      system(env, TEMPLATE, *args, in: File.join(dir, "event"), out: out, err: err)
      Result.new($?.exitstatus, read_stream(out), read_stream(err))
    end
  end

  # An event that reaches a real check: guard-verified scopes through Target
  # first, so it needs a real bundle root or it declines to apply.
  def attesting_event(bundle_dir)
    JSON.generate("tool_name" => "Edit", "cwd" => File.dirname(bundle_dir),
      "tool_input" => { "file_path" => File.join(bundle_dir, "reference/x.md"),
                        "new_string" => "verified: 2026-08-15" })
  end

  # ── the refusals ──────────────────────────────────────────────────────────

  def test_no_check_name_refuses
    with_okf_on_path do |env|
      result = drill(env)

      assert_equal 2, result.status
      assert_match(/ENFORCEMENT MISCONFIGURED/, result.err)
      assert_match(/no check name/, result.err)
    end
  end

  def test_no_okf_on_path_refuses
    Dir.mktmpdir("no-okf-") do |empty|
      path = "#{empty}:/usr/bin:/bin"
      skip "an okf is installed under /usr/bin or /bin on this host" if system({ "PATH" => path },
        "command -v okf > /dev/null 2>&1")

      result = drill(cleared_bundler_env.merge("PATH" => path), "cap-check")

      assert_equal 2, result.status
      assert_match(/is not on PATH/, result.err)
    end
  end

  # The demonstrated fail-open this file exists for. `okf/exe/okf` is
  # `exit OKF::CLI.start(ARGV)` and dispatch calls #call with no rescue, so a
  # LoadError out of the deferred `require "okf/pro"` is a ScriptError —
  # outside every rescue on the path, including discovery's, which catches
  # LoadError and StandardError only. Measured before the fix: process exit 1,
  # which the protocol reads as "proceed", and the edit landed unchecked.
  def test_okf_present_but_the_pro_library_is_unloadable_refuses
    Dir.mktmpdir("no-pro-lib-") do |lib|
      # The seam, without the library behind it: exactly what a half-installed
      # or partially-deleted gem looks like from okf's side.
      FileUtils.mkdir_p(File.join(lib, "okf"))
      FileUtils.cp(File.join(PRO_LIB, "okf", "plugin.rb"), File.join(lib, "okf", "plugin.rb"))
      script = <<~SH
        #!/bin/sh
        exec ruby -I#{lib} -I#{OKF_ROOT}/lib #{OKF_ROOT}/exe/okf "$@"
      SH
      with_okf_on_path(script, isolated: true) do |env|
        result = drill(env, "cap-check")

        assert_equal 2, result.status, "a LoadError out of the deferred require exits 1 — non-blocking — unless it is caught"
      end
    end
  end

  # And plain absence: no okf-pro anywhere, so `pro` is not a verb at all.
  def test_okf_without_okf_pro_installed_refuses
    script = <<~SH
      #!/bin/sh
      exec ruby -I#{OKF_ROOT}/lib #{OKF_ROOT}/exe/okf "$@"
    SH
    with_okf_on_path(script, isolated: true) do |env|
      result = drill(env, "cap-check")

      assert_equal 2, result.status
    end
  end

  # A SyntaxError in plugin.rb is a ScriptError too, and discovery does not
  # catch it either — the whole CLI dies with a parse dump and exit 1, and no
  # okf-pro code runs at all. Neither Ruby-side guard can reach this one; the
  # wrapper is the only thing that can, and it is why it stopped `exec`ing.
  def test_a_syntax_error_in_the_plugin_file_refuses
    Dir.mktmpdir("broken-plugin-") do |lib|
      FileUtils.mkdir_p(File.join(lib, "okf"))
      File.write(File.join(lib, "okf", "plugin.rb"), "this is( not ruby\n")
      script = <<~SH
        #!/bin/sh
        exec ruby -I#{lib} -I#{OKF_ROOT}/lib #{OKF_ROOT}/exe/okf "$@"
      SH
      with_okf_on_path(script) do |env|
        result = drill(env, "cap-check")

        assert_equal 2, result.status, "a SyntaxError in plugin.rb exits 1 — non-blocking — unless the wrapper refuses"
      end
    end
  end

  # Status alone cannot tell a stray shim from a clean gate: both are 0. That is
  # why identity is proved separately, and why the prototype's answer — "just
  # normalise the exit codes" — did not close it. Measured: a shim exiting 0
  # maps to 0 and every gate is off, in silence.
  def test_a_stray_okf_that_exits_zero_refuses
    with_okf_on_path("#!/bin/sh\nexit 0\n") do |env|
      result = drill(env, "cap-check")

      assert_equal 2, result.status, "an okf that exits 0 without identifying itself is a shim, not the enforcer"
      assert_match(/did not identify itself as the enforcer/, result.err)
    end
  end

  # Anything that is not 0 or 2 means nothing to the protocol, so it must not be
  # allowed to mean "fine" by being passed through.
  def test_an_exit_code_the_gate_did_not_choose_refuses
    script = <<~SH
      #!/bin/sh
      echo "okf-pro-enforcer v1" >&2
      exit 7
    SH
    with_okf_on_path(script) do |env|
      result = drill(env, "cap-check")

      assert_equal 2, result.status
      assert_match(/exited 7/, result.err)
    end
  end

  def test_an_unknown_check_name_refuses
    with_okf_on_path do |env|
      result = drill(env, "no-such-check")

      assert_equal 2, result.status
      assert_match(/ENFORCEMENT MISCONFIGURED/, result.err)
    end
  end

  # The whitelist. `Pro::CLI.run` dispatches the CI verbs off the same first
  # argv element a check name arrives in, so an adapter that only stripped
  # `hook` would make this run `okf pro audit` — measured status 0, "clean.",
  # reading no stdin and never blocking. One typo in settings.json and the gate
  # is a gate that always says fine.
  def test_hook_audit_refuses_rather_than_running_the_ci_verb
    with_okf_on_path do |env|
      result = drill(env, "audit")

      assert_equal 2, result.status
      refute_match(/clean\./, result.out, "the CI verb must not have run")
    end
  end

  # ── what must still get through ───────────────────────────────────────────

  def test_the_event_on_stdin_reaches_the_check
    script = <<~SH
      #!/bin/sh
      echo "okf-pro-enforcer v1" >&2
      body="$(cat)"
      [ -n "$body" ] && exit 0
      exit 9
    SH
    with_okf_on_path(script) do |env|
      result = drill(env, "cap-check", event: '{"tool_input":{"file_path":"/b/x.md"}}')

      assert_equal 0, result.status, "the event JSON must reach the check untouched"
    end
  end

  # The most load-bearing gate in the system routes its decision to the owner by
  # printing a PreToolUse `ask` on STDOUT and exiting 0. The prototype's own fix
  # for this file captured stdout in a command substitution and swallowed it:
  # the ask became a hard block, and SessionStart's banner vanished with it.
  def test_an_ask_reaches_stdout_intact
    with_bundle(nested: true) do |b|
      b.concept("reference/x.md", type: "Briefing")
      with_okf_on_path do |env|
        result = drill(env, "guard-verified", event: attesting_event(b.bundle_path))

        assert_equal 0, result.status
        decision = JSON.parse(result.out)["hookSpecificOutput"]
        assert_equal "ask", decision["permissionDecision"]
        assert_match(/owner attestation/, decision["permissionDecisionReason"])
      end
    end
  end

  def test_the_session_banner_reaches_stdout
    with_bundle do |b|
      b.in_flight("one")
      with_okf_on_path do |env|
        result = drill(env, "session-context", event: JSON.generate("cwd" => b.path))

        assert_equal 0, result.status
        assert_match(%r{in flight 1/5}, result.out)
      end
    end
  end

  # The marker is the wrapper's business and nobody else's: a check that said
  # nothing must read as silent downstream, or every clean pass looks like a
  # finding in the agent's transcript.
  def test_the_identity_marker_is_stripped_from_what_reaches_the_agent
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      with_okf_on_path do |env|
        event = JSON.generate("tool_name" => "Edit", "cwd" => b.path,
          "tool_input" => { "file_path" => File.join(b.path, "glossary/term.md") })
        result = drill(env, "check-okf", event: event)

        assert_equal 0, result.status
        assert_empty result.err
      end
    end
  end

  # ── bundler scoping ───────────────────────────────────────────────────────

  # okf finds its extensions with Gem.find_latest_files, which is bundle-scoped
  # once bundler's variables are exported — so inside a bundle that does not name
  # okf-pro, `okf pro` is an unknown command and every gate is silently off.
  # Measured: `BUNDLE_GEMFILE=okf/Gemfile bundle exec okf tui --help` → unknown
  # command, exit 2. The wrapper restores the pre-bundler environment from
  # bundler's OWN restoration data, so it does not depend on a variable list that
  # changes between bundler versions.
  def test_a_bundled_environment_does_not_switch_the_gates_off
    with_bundle do |b|
      b.concept("glossary/term.md", type: "Term")
      bundled = {
        "RUBYOPT" => "-rbundler/setup",
        "BUNDLE_GEMFILE" => File.join(OKF_ROOT, "Gemfile"),
        "BUNDLER_ORIG_RUBYOPT" => "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL",
        "BUNDLER_ORIG_BUNDLE_GEMFILE" => "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL"
      }
      with_okf_on_path(env: bundled) do |env|
        event = JSON.generate("tool_name" => "Edit", "cwd" => b.path,
          "tool_input" => { "file_path" => File.join(b.path, "glossary/term.md") })
        result = drill(env, "check-okf", event: event)

        assert_equal 0, result.status, "the wrapper must restore discovery rather than let the bundle hide it"
      end
    end
  end

  # And the other direction, which the fix itself broke: inside a bundle
  # `Gem.find_latest_files("okf/plugin.rb")` returns nothing at all, so a repo
  # that deliberately vendors okf-pro through its own Gemfile is served ONLY
  # by the unstripped run. The wrapper therefore tries unstripped first.
  def test_the_unstripped_attempt_comes_first_so_an_in_bundle_install_still_works
    script = <<~SH
      #!/bin/sh
      # Answers only while RUBYOPT is still set — i.e. only on the first,
      # unstripped attempt. A wrapper that stripped up front would never see it.
      if [ -n "${RUBYOPT:-}" ]; then
        echo "okf-pro-enforcer v1" >&2
        exit 0
      fi
      exit 1
    SH
    with_okf_on_path(script, env: { "RUBYOPT" => "-rbundler/setup",
                                    "BUNDLER_ORIG_RUBYOPT" => "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL" }) do |env|
      assert_equal 0, drill(env, "cap-check").status
    end
  end

  def test_the_fallback_can_be_pinned_off
    script = <<~SH
      #!/bin/sh
      if [ -n "${RUBYOPT:-}" ]; then exit 1; fi
      echo "okf-pro-enforcer v1" >&2
      exit 0
    SH
    env_vars = { "RUBYOPT" => "-rbundler/setup",
                 "BUNDLER_ORIG_RUBYOPT" => "BUNDLER_ENVIRONMENT_PRESERVER_INTENTIONALLY_NIL" }
    with_okf_on_path(script, env: env_vars) do |env|
      assert_equal 0, drill(env, "cap-check").status, "without the pin, the stripped retry finds it"
    end
    with_okf_on_path(script, env: env_vars.merge("OKF_PRO_NO_UNBUNDLE" => "1")) do |env|
      assert_equal 2, drill(env, "cap-check").status, "pinned, the wrapper never strips and refuses instead"
    end
  end

  # ── the path a person actually has ────────────────────────────────────────

  # `"$CLAUDE_PROJECT_DIR"` stays quoted in settings.json, and this is why:
  # unquoted, a spaced path word-splits, the shell exits 127, and 127 is
  # non-blocking — all four gates disarmed by a directory name.
  def test_a_project_path_containing_a_space_still_gates
    Dir.mktmpdir("spaced ") do |root|
      dir = File.join(root, "my brain")
      FileUtils.mkdir_p(dir)
      with_okf_on_path do |env|
        result = drill(env, "session-context", event: JSON.generate("cwd" => dir))

        assert_equal 0, result.status
      end
    end
  end
end

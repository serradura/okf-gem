# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The hook table itself, tested as the configuration it is: every command
# must survive a checkout path containing a space. Unquoted, the shell
# word-split `$CLAUDE_PROJECT_DIR/.claude/hooks/run guard-verified` into
# `/Users/x/My` plus arguments and exited 127 — which the hook protocol
# reads as NON-BLOCKING, so a spaced clone silently disarmed all four gates
# at once. The stub records its first argument, so this also proves the
# check name still arrives intact after quoting.
class SettingsTest < OKF::Pro::TestCase
  # The template's, not this repository's. The scaffold is the thing under
  # test: an adopter's settings.json is a copy of that file, and this gem does
  # not run its own hooks against its own bundle.
  SETTINGS = File.expand_path("../../lib/okf/pro/template/seed/.claude/settings.json", __dir__)

  def hook_commands
    JSON.parse(OKF::Pro.read_text(SETTINGS))["hooks"]
        .values.flatten
        .flat_map { |entry| entry["hooks"] }
        .map { |hook| hook["command"] }
  end

  def test_every_hook_command_survives_a_project_path_with_spaces
    commands = hook_commands
    refute_empty commands

    Dir.mktmpdir("proj space-") do |dir|
      hooks = File.join(dir, ".claude", "hooks")
      FileUtils.mkdir_p(hooks)
      marker = File.join(dir, "invoked")
      stub = File.join(hooks, "run")
      File.write(stub, "#!/bin/sh\nprintf '%s\\n' \"$1\" >> \"#{marker}\"\nexit 0\n")
      File.chmod(0o755, stub)

      commands.each do |cmd|
        system({ "CLAUDE_PROJECT_DIR" => dir }, "sh", "-c", cmd,
          in: File::NULL, out: File::NULL, err: File::NULL)
        assert_equal 0, $?.exitstatus, "hook command failed under a spaced path: #{cmd}"
      end

      invoked = File.read(marker).split("\n").sort
      assert_equal %w[guard-verified journal-guard post-edit session-context shell-guard stop-gate],
        invoked
    end
  end
end

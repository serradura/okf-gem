# frozen_string_literal: true

require "test_helper"
require "okf/cli"

# The command registry's own contract, in the shape the search engines' one
# already takes: registering is not enough, and the properties every registered
# command must answer are asserted against the registry rather than against a
# list someone remembered to update.
class RegisteredCommandsConformTest < OKF::TestCase
  # The verbs this gem ships, in the order `okf help` lists them. This is a
  # deliberate duplicate of the require block at the bottom of cli.rb: the
  # coupling lives there, and this is what stops it drifting unnoticed.
  BUILTINS = %i[
    skill server render registry lint loose validate
    search index stats types tags files catalog graph
  ].freeze

  test "the built-ins are exactly these, in this order" do
    assert_equal BUILTINS, OKF::CLI.builtins.map(&:id),
      "the require order at the bottom of cli.rb IS the map's order — changing it changes what a user reads"
  end

  test "every registered command answers the whole duck type" do
    OKF::CLI.commands.each do |command|
      assert_kind_of Symbol, command.id
      assert_kind_of Symbol, command.group
      assert_kind_of Array, command.help_rows
      assert_includes [ true, false ], command.hidden?
      assert command.ancestors.include?(OKF::CLI::Command),
        "#{command.id} must inherit Command — the shared surface is not optional"
    end
  end

  test "every visible command carries a help row — registering is not enough" do
    OKF::CLI.commands.reject(&:hidden?).each do |command|
      refute_empty command.help_rows,
        "#{command.id} dispatches but says nothing in the map, which is how a verb becomes unfindable"
      command.help_rows.each do |left, desc|
        refute OKF.blank?(left), "#{command.id} has a help row with no grammar"
        refute OKF.blank?(desc), "#{command.id} has a help row with no description"
      end
    end
  end

  test "a help row leads with the verb it documents" do
    # The map is scanned down its left edge; a row that does not start with its
    # own verb is a row nobody finds by looking for the command.
    OKF::CLI.commands.reject(&:hidden?).each do |command|
      command.help_rows.each do |row|
        left = row.first
        assert left.start_with?(command.id.to_s),
          "#{command.id}'s row starts #{left.inspect}, so it does not sort under its own verb"
      end
    end
  end

  test "every built-in declares a group the map actually prints" do
    groups = OKF::CLI::GROUPS.map(&:first)

    OKF::CLI.builtins.each do |command|
      assert_includes groups, command.group,
        "#{command.id} is in group #{command.group.inspect}, which GROUPS never prints — the verb would vanish from help"
    end
  end

  test "ids are unique, so no verb is unreachable" do
    ids = OKF::CLI.commands.map(&:id)

    assert_equal ids.uniq, ids
  end

  test "registration is idempotent by id" do
    before = OKF::CLI.commands.length

    assert_equal OKF::CLI::Lint, OKF::CLI.register(OKF::CLI::Lint)
    assert_equal before, OKF::CLI.commands.length, "re-registering the same class is a no-op"
  end

  test "a class that is not a command is refused, and says what it lacks" do
    error = assert_raises(ArgumentError) { OKF::CLI.register(Class.new) }

    assert_match(/does not answer/, error.message)
  end

  test "the plugin file is a convention, not a list of known addons" do
    # The base gem naming its own addons is the coupling this seam exists to
    # avoid; a grep is the cheapest way to keep it that way.
    # Explicit encoding: the 2.4 Docker check runs with no locale, so
    # Encoding.default_external is US-ASCII and a plain read tags this file's
    # em-dashes as invalid bytes — which then raises the moment a regexp meets
    # them. The same reason cli_integration_case#read_utf8 exists.
    source = File.read(File.expand_path("../../../lib/okf/cli.rb", __dir__), encoding: "UTF-8")

    assert_equal "okf/plugin.rb", OKF::CLI::PLUGIN_FILE
    refute_match(/okf-tui|okf\/tui|okf-mcp|okf-sqlite3/, source,
      "cli.rb must not name a specific addon — discovery is by convention")
  end
end

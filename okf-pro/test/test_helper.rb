# frozen_string_literal: true

# Minitest's progress dots go through a pipe on CI, where stdout is block-
# buffered — so a run that wedges flushes nothing and the log cannot say which
# test it stopped after. Syncing makes a hang name itself.
$stdout.sync = true

# Coverage, where the Ruby can install simplecov. The gem's floor is 2.4 and
# simplecov's is not, so this is `rescue LoadError` rather than a dependency:
# the floor run proves the suite, not the report.
begin
  require "simplecov"

  gem_root = File.expand_path("..", __dir__) # okf-pro/

  SimpleCov.start do
    # Branch as well as line. This gem is mostly branches, and a gate whose
    # every line ran but whose refusal arm never did is tested only on the path
    # where it says yes — which is the half that does not matter.
    enable_coverage :branch
    root gem_root
    add_filter "/test/"
    coverage_dir File.expand_path(ENV["OKF_PRO_COVERAGE_DIR"] || "coverage", gem_root)
    command_name ENV["OKF_PRO_COVERAGE_NAME"] if ENV["OKF_PRO_COVERAGE_NAME"]
  end
  SimpleCov.external_at_exit = true
rescue LoadError
  # no coverage on this Ruby
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"
require "json"
require "okf/pro"

Minitest.after_run { SimpleCov.at_exit_behavior } if defined?(SimpleCov)

# A real OKF bundle on disk, in a temp directory.
#
# The checks that matter most are the ones that consult the corpus — validate,
# lint, search, pairing — and none of them can be tested against a mock without
# testing the mock instead. So the fixture is a genuine bundle: `okf` reads it
# the same way it reads the repo, and a test that says "this lints clean" has
# actually run the linter.
#
# Note what that makes it: a *client of the code under test*. `write_log` calls
# `Snapshot.line`, so a change to the counters reaches every fixture that
# carries a log day. That is deliberate — a fixture with a hand-typed snapshot
# line drifts from its own board exactly the way a person's does — but it means
# "the ported suite is unchanged proof" holds only until a work item touches
# what the fixture calls.
module BundleFixture
  BundleRootDir = OKF::Pro::BundleRoot::DIR

  DEFAULT_BOARD_SECTIONS = [ "In flight", "Backlog", "Waiting", "Inbox", "To read", "Deadlines" ].freeze

  # Yields a Bundle. Nothing is written until `#path` is asked for, so a test
  # configures and uses it in one block and the directory disappears with it.
  def with_bundle(git: false, nested: false)
    Dir.mktmpdir("pro-test-") do |dir|
      yield Bundle.new(dir, git: git, nested: nested)
    end
  end

  class Bundle
    attr_reader :dir

    # `root` is the repository — what a hook event's cwd points at. `dir` is
    # the bundle root, which is the same directory unless the fixture is
    # nested, in which case it is `root/.okf` and finding it is the checker's
    # job rather than the caller's.
    def initialize(dir, git: false, nested: false)
      @root = dir
      @dir = nested ? File.join(dir, BundleRootDir) : dir
      @git = git
      @finished = false
      @concepts = {}
      @indexes = {}
      @raw = {}
      @sections = {}
      @declared = nil
      @cap = 5
      @log_days = {}
      @snapshot_day = nil
    end

    # Writing everything is deferred to here so `#concept` and friends can be
    # called in any order — the indexes and the board have to be written last
    # because they enumerate what came before.
    def path
      finish unless @finished
      @root
    end

    # Where the concepts actually landed. Equal to `path` unless nested.
    def bundle_path
      finish unless @finished
      dir
    end

    def write(rel, content)
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    # A concept with frontmatter. `body` gets a link back to the board by
    # default so the fixture does not trip lint's reachability info for reasons
    # unrelated to the test.
    def concept(rel, type:, title: nil, description: nil, body: nil, **extra)
      title ||= File.basename(rel, ".md").split("-").map(&:capitalize).join(" ")
      description ||= "Fixture concept #{title}."
      front = { "type" => type, "title" => title, "description" => description }
              .merge(deep_stringify(extra))
      @concepts[rel] = [ front, body || "# #{title}\n\nFixture body long enough to clear the stub threshold.\n" ]
      self
    end

    # Frontmatter written verbatim, for the shapes a Hash cannot express (or
    # that a test wants malformed on purpose).
    def raw(rel, content)
      @raw[rel] = content
      self
    end

    # Symbol keys survive into YAML as `:key:`, which is not what any of these
    # fixtures mean. Frontmatter is string-keyed all the way down.
    def deep_stringify(value)
      case value
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
      when Array then value.map { |v| deep_stringify(v) }
      else value
      end
    end

    def in_flight(*lines)
      board_lines("In flight", *lines)
    end

    def inbox(*lines)
      board_lines("Inbox", *lines)
    end

    # Any board section by name — Waiting, To read, Deadlines — for the checks
    # that read further down the page than the budget does.
    def board_lines(section, *lines)
      (@sections[section] ||= []).concat(lines)
      self
    end

    # Declared defaults to the true count; pass it explicitly to build a board
    # whose header lies about its own section.
    def budget(declared: nil, cap: 5)
      @declared = declared
      @cap = cap
      self
    end

    def log_day(day, *entries)
      @log_days[day] = entries
      self
    end

    # The day's Snapshot line, computed by the module under test rather than
    # typed here — the stop gate verifies counters now, and a fixture carrying
    # a hand-typed line would drift from its own board the way a person's does.
    # Tests about drift write their wrong line through log_day directly.
    def snapshot_on(day)
      @snapshot_day = day
      self
    end

    def finish
      @finished = true
      ensure_core
      write_concepts
      write_indexes
      write_board
      write_root_index
      write_log
      system("git", "init", "-q", @root, out: File::NULL, err: File::NULL) if @git
      @root
    end

    private

    # The closed core the audit enforces. A fixture bundle carries it by
    # default — the fixtures are meant to be real bundles, and a real bundle
    # without its skeleton is the *subject* of a test, not its backdrop.
    def ensure_core
      unless @concepts.key?("areas/corpus.md") || @raw.key?("areas/corpus.md")
        concept("areas/corpus.md", type: "Overview", title: "Corpus",
          description: "The standard this fixture corpus is kept at.")
      end
      write("journal/index.md", "# Journal\n\nOne entry per day.\n")
    end

    def write_concepts
      @concepts.each do |rel, (front, body)|
        write(rel, "#{YAML.dump(front)}---\n\n#{body}")
      end
      @raw.each { |rel, content| write(rel, content) }
    end

    # One index per directory holding concepts, listing every one of them —
    # lint warns on an index that links to a concept that is not there, and on
    # a directory whose index omits one.
    def write_indexes
      (@concepts.keys + @raw.keys).group_by { |rel| File.dirname(rel) }.each do |dir_name, rels|
        next if dir_name == "."

        lines = rels.reject { |r| File.basename(r) == "index.md" }.map do |rel|
          name = File.basename(rel, ".md")
          "* [#{name}](#{File.basename(rel)}) - fixture entry."
        end
        next if lines.empty?

        write(File.join(dir_name, "index.md"), "# #{dir_name.capitalize}\n\n#{lines.join("\n")}\n")
      end
    end

    def write_board
      declared = @declared || (@sections["In flight"] || []).size
      sections = DEFAULT_BOARD_SECTIONS.map do |name|
        body = @sections[name] || []
        "## #{name}\n#{body.map { |l| "- #{l}" }.join("\n")}\n"
      end
      write("board.md", <<~BOARD)
        ---
        type: Board
        title: Board
        description: Fixture board.
        ---

        # Board

        **In flight: #{declared}/#{@cap}** · updated fixture

        #{sections.join("\n")}
      BOARD
    end

    def write_log
      if @snapshot_day
        line = OKF::Pro::Snapshot.line(dir, today: Date.parse(@snapshot_day))
        (@log_days[@snapshot_day] ||= []) << line
      end
      days = @log_days.sort.reverse.map do |day, entries|
        "## #{day}\n#{entries.join("\n")}\n"
      end
      write("log.md", "# Update Log\n\n#{days.join("\n")}")
    end

    def write_root_index
      write("index.md", "---\nokf_version: \"0.2\"\n---\n\n# Fixture\n\n* [board.md](/board.md) - state.\n")
    end
  end

  # ── event construction ────────────────────────────────────────────────────

  def event(**attrs)
    OKF::Pro::Event.new(JSON.generate(stringify(attrs)))
  end

  def write_event(dir, rel, **tool_input)
    event(tool_name: "Write", cwd: dir,
      tool_input: { file_path: File.join(dir, rel) }.merge(tool_input))
  end

  def edit_event(dir, rel, **tool_input)
    event(tool_name: "Edit", cwd: dir,
      tool_input: { file_path: File.join(dir, rel) }.merge(tool_input))
  end

  def stringify(value)
    case value
    when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify(v) }
    when Array then value.map { |v| stringify(v) }
    else value
    end
  end

  # ── the real entry point, on a real PATH ──────────────────────────────────
  #
  # Two doors reach this gem the way a user does — the Claude Code wrapper and
  # the pre-commit hook — and both resolve `okf` from PATH. Testing either
  # against anything else tests the fixture.

  # The okf checkout this suite resolves. The Gemfile points it at ../okf.
  OKF_ROOT = Gem.loaded_specs.key?("okf") ? Gem.loaded_specs["okf"].full_gem_path : File.expand_path("../../okf", __dir__)
  PRO_LIB = File.expand_path("../lib", __dir__)

  # Bundler's variables reach a child process and put this gem's lib on the load
  # path through the bundle rather than through the shim's own -I. Left in
  # place, a drill would be answered partly by the suite's own environment — and
  # "okf-pro is absent" would find it anyway and pass at 0.
  def cleared_bundler_env
    ENV.keys.grep(/\A(RUBYOPT|BUNDLE_|BUNDLER_)/).each_with_object({}) { |k, h| h[k] = nil }
  end

  # A subprocess's captured stream, read the way `Pro.read_text` reads a file
  # and for the same reason: with LANG unset — the normal state in a container, a
  # CI step and a git hook — `Encoding.default_external` is US-ASCII, and a plain
  # `File.read` tags these bytes as invalid. Every refusal message here carries an
  # em dash, so the first `assert_match` against one raises `ArgumentError`
  # instead of failing or passing.
  #
  # Found by the 2.4 floor container, which runs with no locale at all: seven
  # wrapper drills errored there while passing everywhere else.
  def read_stream(path)
    File.read(path, mode: "rb").force_encoding(Encoding::UTF_8).scrub
  end

  # A directory holding an `okf` executable, put first on PATH. `body` is the
  # shell script's body; the default is the real thing — okf's own exe with this
  # gem's lib on the load path, which is what an installed pair amounts to.
  #
  # `isolated: true` models a machine where okf-pro is NOT installed. It has to
  # be modelled rather than assumed: a maintainer who ran `gem install okf-pro`
  # to try the verb has one on the machine, and okf discovers `okf/plugin.rb` in
  # every installed gem as well as on the load path. Both files then load, and
  # the second reopens OKF::CLI::Pro and redefines the first's methods — so a
  # drill asserting "okf-pro is absent" finds it anyway and passes at 0, which
  # is the one thing those drills exist to rule out.
  def with_okf_on_path(body = nil, env: {}, isolated: false)
    Dir.mktmpdir("okf-bin-") do |bin|
      prelude = isolated ? "-r#{write_isolation_prelude(bin)} " : ""
      script = body || "#!/bin/sh\nexec ruby #{prelude}-I#{OKF_ROOT}/lib -I#{PRO_LIB} #{OKF_ROOT}/exe/okf \"$@\"\n"
      script = script.sub("exec ruby ", "exec ruby #{prelude}") if body && isolated
      File.write(File.join(bin, "okf"), script)
      File.chmod(0o755, File.join(bin, "okf"))
      yield(cleared_bundler_env.merge("PATH" => "#{bin}:#{ENV.fetch("PATH", nil)}").merge(env))
    end
  end

  # Makes an installed okf-pro invisible to RubyGems for the length of one
  # subprocess, which is what "okf-pro is not installed" has to mean on a
  # machine where a maintainer has run `gem install okf-pro` to try the verb.
  #
  # Narrowing discovery is not enough, and the first attempt at this proved it:
  # filtering `Gem.find_latest_files` hid the plugin, and then `require
  # "okf/pro"` ACTIVATED the installed gem anyway and the check ran — a drill
  # about absence, passing at 0, because of the very gem it was asserting away.
  # Dropping the spec closes both doors at once: nothing discovers it and
  # nothing can activate it.
  #
  # It removes one spec and touches nothing else, so the drill still runs okf's
  # real `plugin_paths`, its `require`, and its rescue.
  def write_isolation_prelude(dir)
    path = File.join(dir, "no_installed_okf_pro.rb")
    File.write(path, <<~RUBY)
      require "rubygems"
      Gem::Specification.all = Gem::Specification.reject { |spec| spec.name == "okf-pro" }
    RUBY
    path
  end

  # ── running the CLI with captured streams ─────────────────────────────────

  Run = Struct.new(:status, :out, :err) do
    # stderr as a reader downstream of the wrapper sees it. `okf pro hook`
    # writes its identity marker there as the first act of every check, and
    # `.claude/hooks/run` strips that line before passing the rest on — so a
    # test asking "did this check say anything?" must strip it too, or every
    # silent pass reads as a finding.
    def findings
      err.sub(/\A#{Regexp.escape(OKF::Pro::CLI::MARKER)}\n/, "")
    end

    def identified?
      err.start_with?("#{OKF::Pro::CLI::MARKER}\n")
    end
  end

  def run_cli(argv, stdin: "")
    out = StringIO.new
    err = StringIO.new
    status = OKF::Pro::CLI.run(argv.dup, stdin: StringIO.new(stdin), stdout: out, stderr: err)
    Run.new(status, out.string, err.string)
  end
end

module OKF
  module Pro
    # The kernel's declarative Minitest sugar, ported so the suites read alike
    # across the monorepo: `test "name" do ... end` plus block setup/teardown.
    # The suite runs on 2.4 too, so ../AGENTS.md's API constraints apply here.
    class TestCase < Minitest::Test
      include BundleFixture

      # The shipped skill, as one string.
      #
      # Three pins couple a constant in `lib/` to a number or a spelling the
      # skill teaches, and each used to read `SKILL.md` by path. The skill is a
      # directory now, so a section moving from the entry point into a guide
      # took the coupling out of view — the closure-grammar pin failed with
      # "enumerates no closure spelling at all", which is the right complaint
      # about the wrong thing. Reading the whole directory makes a pin care that
      # the skill says it, not where.
      SKILL_DIR = File.expand_path(
        "../lib/okf/pro/template/gem/.claude/skills/okf-pro", __dir__
      )

      def skill_text
        Dir.glob(File.join(SKILL_DIR, "**", "*.md")).sort.map { |path| OKF::Pro.read_text(path) }.join("\n")
      end

      # The paragraph carrying a `<!-- rule: <key> -->` marker.
      #
      # A pin that couples a constant here to a number the skill states has to
      # find that statement somehow, and matching on prose formatting — the
      # paragraph that happens to contain `**5 working days**` — is a positional
      # reference wearing a regex. Reword the sentence and the coupling either
      # breaks or, worse, starts matching a different paragraph. The key travels
      # with the text it names, through a rewrite and through a move into
      # another file.
      def skill_rule(key)
        paragraphs = skill_text.split(/\n[ \t]*\n/)
        found = paragraphs.select { |para| para.include?("<!-- rule: #{key} -->") }

        if found.empty?
          raise "no skill paragraph carries `<!-- rule: #{key} -->` — the key was renamed or dropped, " \
                "and the rule it named is now uncited"
        end

        found.join("\n")
      end

      class << self
        def test(name, &block)
          method_name = "test_#{name.gsub(/\W+/, "_")}"
          raise ArgumentError, "duplicate test name: #{name}" if method_defined?(method_name)

          define_method(method_name, &block)
        end

        def setup(&block)
          define_method(:setup) do
            super()
            instance_eval(&block)
          end
        end

        def teardown(&block)
          define_method(:teardown) do
            instance_eval(&block)
            super()
          end
        end
      end
    end
  end
end

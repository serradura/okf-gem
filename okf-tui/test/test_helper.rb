# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "okf/tui"
require "minitest/autorun"
require "minitest/mock"
require "stringio"
require "tmpdir"
require "fileutils"

module OKF
  module TUI
    # Pins the terminal size for the duration of a block, so a rendered frame is
    # reproducible on any terminal — including none at all.
    module FixedScreen
      class << self
        attr_reader :width, :height

        def with(width, height)
          previous = [ @width, @height ]
          @width = width
          @height = height
          install
          yield
        ensure
          @width, @height = previous
        end

        def install
          return if @installed

          TTY::Screen.singleton_class.prepend(Overrides)
          @installed = true
        end
      end

      module Overrides
        def width
          FixedScreen.width || super
        end

        def height
          FixedScreen.height || super
        end
      end
    end

    # Plain Minitest plus `test "..."` / block `setup` sugar, mirroring okf's own
    # OKF::TestCase. The suite runs on 2.4 too, so the API constraints in
    # AGENTS.md apply to test/ as well.
    class TestCase < Minitest::Test
      FIXTURES = File.expand_path("fixtures", __dir__)

      # Named keys, so a script reads as what a user actually pressed.
      NAMED = {
        "<down>" => App::DOWN, "<up>" => App::UP, "<tab>" => App::TAB,
        "<enter>" => "\r", "<esc>" => App::ESCAPE, "<bs>" => App::DELETE,
        "<space>" => " "
      }.freeze

      class << self
        def test(name, &block)
          define_method("test_#{name.gsub(/\W+/, "_")}", &block)
        end

        def setup(&block)
          define_method(:setup, &block)
        end

        def teardown(&block)
          define_method(:teardown, &block)
        end
      end

      def fixture(name)
        File.join(FIXTURES, name.to_s)
      end

      # A registry under a temporary $OKF_HOME. Nothing here ever touches the
      # real ~/.okf — that is the user's configuration, not the suite's.
      #
      # The env var is *set*, not merely yielded, because it is the only lever
      # the CLI offers now that --home is gone: a test that drives argv has no
      # other way to say which registry it means. The `home` it still yields is
      # for the library API (App/Workspace take `home:`), which an embedding app
      # reaches without mutating a process-global.
      #
      # OKF_NO_DISCOVERY goes with it, because $OKF_HOME alone does not name a
      # registry — it names where the *global* one lives, and deliberately does
      # not veto a nearer project-local `.okf-registry.json` on the path up from
      # cwd. The suite runs from okf-tui/, which sits inside a repository that
      # commits one, so without this the run resolves to the maintainer's tree
      # rather than to `home`. This helper means the global registry; the local
      # one has its own helper below, which is where discovery is left on.
      def with_registry(*names)
        home = Dir.mktmpdir("okf-tui-home")
        was = ENV.fetch("OKF_HOME", nil)
        discovery_was = ENV.fetch("OKF_NO_DISCOVERY", nil)
        ENV["OKF_HOME"] = home
        ENV["OKF_NO_DISCOVERY"] = "1"
        registry = OKF::Registry.load(home: home)
        names.each { |name| registry.add(fixture(name)) }
        yield home, registry
      ensure
        was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = was
        discovery_was.nil? ? ENV.delete("OKF_NO_DISCOVERY") : ENV["OKF_NO_DISCOVERY"] = discovery_was
        FileUtils.remove_entry(home) if home && File.directory?(home)
      end

      # A project-local `.okf-registry.json` (okf 1.12) in a fresh directory, with
      # an empty global $OKF_HOME beside it. Yields the project directory, the
      # local registry, and the global one — three things, because the only way to
      # prove a run resolved to the local file is to register something different
      # in the global one and show it is not what came back.
      #
      # $OKF_HOME is set rather than left alone so that a test which forgets to
      # arrange discovery reads an empty temporary registry instead of the
      # maintainer's real ~/.okf.
      def with_local_registry(*names)
        root = Dir.mktmpdir("okf-tui-local")
        project = File.join(root, "project")
        home = File.join(root, "home")
        FileUtils.mkdir_p(project)
        was = ENV.fetch("OKF_HOME", nil)
        ENV["OKF_HOME"] = home
        local = OKF::Registry.new(File.join(project, OKF::Registry::LOCAL_FILE))
        names.each { |name| local.add(fixture(name)) }
        local.save
        yield project, local, OKF::Registry.load(home: home)
      ensure
        was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = was
        FileUtils.remove_entry(root) if root && File.directory?(root)
      end

      # A temporary $OKF_HOME with nothing in it — the "you have registered
      # nothing" path, which needs an empty registry rather than no registry.
      # OKF_NO_DISCOVERY for the reason #with_registry gives: empty means empty,
      # and a project registry above the checkout would fill it.
      def with_empty_registry
        home = Dir.mktmpdir("okf-tui-empty")
        was = ENV.fetch("OKF_HOME", nil)
        discovery_was = ENV.fetch("OKF_NO_DISCOVERY", nil)
        ENV["OKF_HOME"] = home
        ENV["OKF_NO_DISCOVERY"] = "1"
        yield home
      ensure
        was.nil? ? ENV.delete("OKF_HOME") : ENV["OKF_HOME"] = was
        discovery_was.nil? ? ENV.delete("OKF_NO_DISCOVERY") : ENV["OKF_NO_DISCOVERY"] = discovery_was
        FileUtils.remove_entry(home) if home && File.directory?(home)
      end

      # An app driven by a script of keys, with no terminal involved.
      #
      # A frame is a pure function of (workspace, keys, size) — `handle` mutates
      # the state exactly as the key loop would, and `paint` renders it into a
      # string. That is what makes the whole UI testable.
      def app_for(dirs: [], home: nil, keys: "", size: [ 100, 30 ])
        app = App.new(dirs: Array(dirs).map { |dir| fixture(dir) }, home: home, output: StringIO.new)
        FixedScreen.with(size[0], size[1]) { keystrokes(keys).each { |key| app.handle(key) } }
        app
      end

      def frame_for(app, size: [ 100, 30 ])
        buffer = StringIO.new
        app.instance_variable_set(:@output, buffer)
        FixedScreen.with(size[0], size[1]) { app.paint }
        buffer.string.gsub(/\e\[\d+;\d+H/, "")
      end

      def render(dirs: [], home: nil, keys: "", size: [ 100, 30 ])
        frame_for(app_for(dirs: dirs, home: home, keys: keys, size: size), size: size)
      end

      def plain(text)
        text.gsub(/\e\[[0-9;]*[a-zA-Z]/, "")
      end

      def keystrokes(script)
        script.to_s.scan(/<[a-z]+>|./m).map { |token| NAMED.fetch(token, token) }
      end
    end
  end
end

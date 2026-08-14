# frozen_string_literal: true

require_relative "mcp_integration_case"
require "okf/mcp/cli"

# The argv shell, in-process: flags, refusals and exit codes, driven straight
# at OKF::MCP::CLI so the coverage report counts them.
#
# Nothing here spawns. There is one entry point — the `okf mcp` verb — and
# cli_plugin_test.rb owns every test that runs it as a real process, so a
# claim about argv is proven once, cheaply, here, and a claim about the
# process is proven once, there.
class CLITest < MCPIntegrationCase
  Result = Struct.new(:status, :out, :err)

  test "--version prints the version and exits 0" do
    result = run_cli("--version")
    assert_equal 0, result.status
    assert_equal OKF::MCP::VERSION, result.out.strip
  end

  test "--help prints usage and exits 0" do
    result = run_cli("--help")
    assert_equal 0, result.status
    assert_match(/usage: okf mcp/, result.out)
    assert_match(/--http/, result.out)
  end

  test "a bad flag is a usage error: exit 2, message and usage on stderr" do
    result = run_cli("--bogus")
    assert_equal 2, result.status
    assert_match(/invalid option: --bogus/, result.err)
    assert_match(/usage: okf mcp/, result.err)
  end

  test "no args and an empty registry is a usage error pointing at okf registry set" do
    result = run_cli
    assert_equal 2, result.status
    assert_match(/no bundles registered — run `okf registry set <dir>`/, result.err)
  end

  test "a nonexistent directory is a usage error" do
    result = run_cli("no/such/dir")
    assert_equal 2, result.status
    assert_match(%r{no such directory: no/such/dir}, result.err)
  end

  test "an unknown ref is a usage error naming the registry file" do
    result = run_cli("@nope")
    assert_equal 2, result.status
    assert_match(/unknown ref @nope/, result.err)
  end

  test "a bare @ with an empty registry is a usage error" do
    result = run_cli("@")
    assert_equal 2, result.status
    assert_match(/no default bundle: the registry is empty/, result.err)
  end

  test "a ref that normalizes to nothing is a bad ref, never a minted name" do
    result = run_cli("@***")
    assert_equal 2, result.status
    assert_match(/unknown ref @\*\*\*/, result.err)
  end

  test "a ref whose registered directory vanished is a usage error at boot" do
    dir = scratch_bundle("goner")
    OKF::Registry.load.add(dir)
    FileUtils.rm_rf(dir)
    result = run_cli("@goner")
    assert_equal 2, result.status
    assert_match(/registered as goner\) is not a directory/, result.err)
  end

  # Every other boot failure above exits 2 with one readable line. A bind that
  # fails did not: `Errno::EADDRINUSE` is a `SystemCallError`, which the rescue
  # did not name, so the most likely `--http` mistake there is — the port is
  # already serving, which is the whole point of a warm process — came back as
  # an eleven-frame Ruby backtrace and exit 1.
  test "a port already in use is a usage error, not a backtrace" do
    require "socket"
    taken = TCPServer.new("127.0.0.1", 0)
    begin
      result = run_cli("--http", "--port", taken.addr[1].to_s, fixture("knowledge"))

      assert_equal 2, result.status
      assert_match(/okf-mcp: .*(in use|EADDRINUSE)/i, result.err)
      assert_match(/usage: okf mcp/, result.err)
      refute_match(%r{lib/okf/mcp}, result.err, "a backtrace reached the operator")
    ensure
      taken.close
    end
  end

  # The same shape one ring out: an out-of-range port or an unresolvable bind
  # raises from the socket layer (SocketError — Socket::ResolutionError on
  # newer Rubies subclasses it), which the boot rescue did not name, so the
  # operator got a backtrace for a typo.
  test "an out-of-range --port or unresolvable --bind is a usage error, not a backtrace" do
    bad_port = run_cli("--http", "--port", "99999", fixture("knowledge"))

    assert_equal 2, bad_port.status
    assert_match(/usage: okf mcp/, bad_port.err)
    refute_match(%r{lib/okf/mcp}, bad_port.err, "a backtrace reached the operator")

    bad_bind = run_cli("--http", "--bind", "no.such.host.invalid.", fixture("knowledge"))

    assert_equal 2, bad_bind.status
    refute_match(%r{lib/okf/mcp}, bad_bind.err, "a backtrace reached the operator")
  end

  # The mirror case: past a successful boot, the likeliest errno is the host
  # closing its pipes — a stdio session's normal end, Claude Desktop quitting
  # after hours of serving. That errno reached the boot rescue, which printed
  # the usage banner and exited 2: a shutdown misfiled as an operator mistake,
  # for any supervisor keyed on the exit status.
  test "a host disconnecting mid-serve is a normal end, not a usage error" do
    err = StringIO.new
    cli = OKF::MCP::CLI.new([ fixture("knowledge") ], out: err, stdout: StringIO.new)
    cli.define_singleton_method(:serve_stdio) { |_server| raise Errno::EPIPE }

    assert_equal 0, cli.run
    refute_match(/usage: okf mcp/, err.string, "a host hanging up is not an operator mistake")
  end

  # The same hang-up, one moment earlier: the host died while boot was still
  # printing. The rescue caught the announce's EPIPE — and then its own puts
  # raised EPIPE again, uncaught: a backtrace and exit 1 for a normal end.
  # Diagnostics are best-effort; a closed stderr loses the boot line, never
  # the exit contract.
  test "a host that closes the pipes during boot is a normal end, not a backtrace" do
    err = StringIO.new
    err.define_singleton_method(:puts) { |*| raise Errno::EPIPE }
    cli = OKF::MCP::CLI.new([ fixture("knowledge") ], out: err, stdout: StringIO.new)
    cli.define_singleton_method(:serve_stdio) { |_server| nil }

    assert_equal 0, cli.run
  end

  # The carve-out is stdio's alone. On --http the boot line already went
  # through best-effort prints, so a hang-up errno escaping the accept loop
  # cannot mean "the session ended" — it is a runtime fault like any other,
  # and reading it as a clean exit 0 would hide a dead shared server from
  # every supervisor keyed on the status.
  test "an --http hang-up errno mid-serve propagates, never a clean exit 0" do
    err = StringIO.new
    cli = OKF::MCP::CLI.new([ "--http", "--port", "0", fixture("knowledge") ], out: err, stdout: StringIO.new)
    cli.define_singleton_method(:prepare_http) do |_server|
      httpd = Object.new
      httpd.define_singleton_method(:start) { raise Errno::ECONNRESET }
      @httpd = httpd
    end

    assert_raises(Errno::ECONNRESET) { cli.run }
  end

  # The carve-out is exactly two errnos wide. Any other mid-serve errno is a
  # runtime fault hours past a valid invocation: routing it through the boot
  # rescue printed the usage banner and exited 2, telling a supervisor the
  # operator's arguments were wrong. It propagates — a crash reads as one.
  test "a runtime errno mid-serve is a crash to report, never a usage error" do
    err = StringIO.new
    cli = OKF::MCP::CLI.new([ fixture("knowledge") ], out: err, stdout: StringIO.new)
    cli.define_singleton_method(:serve_stdio) { |_server| raise Errno::EIO }

    assert_raises(Errno::EIO) { cli.run }
    refute_match(/usage: okf mcp/, err.string, "a runtime fault read as an operator mistake")
  end

  # The flag is repeatable, and its whole job is to reach the HTTP boot: a
  # reverse proxy's Host or a DNS name no local interface knows.
  test "--allow-host is repeatable and reaches the HTTP boot" do
    seen = nil
    cli = OKF::MCP::CLI.new(
      [ "--http", "--allow-host", "proxy.internal", "--allow-host", "edge.internal", "--port", "0", fixture("knowledge") ],
      out: StringIO.new, stdout: StringIO.new
    )
    cli.define_singleton_method(:prepare_http) do |_server|
      seen = @allow_hosts
      httpd = Object.new
      httpd.define_singleton_method(:start) { nil }
      @httpd = httpd
    end

    assert_equal 0, cli.run
    assert_equal %w[proxy.internal edge.internal], seen
  end

  # The one un-stubbed pass through serve_stdio: the SDK transport reads the
  # standard streams, and a stdin already at EOF is the shortest complete
  # session — boot, serve, normal end, exit 0.
  test "a stdio session ends cleanly when stdin reaches EOF" do
    was = $stdin
    $stdin = StringIO.new("")
    cli = OKF::MCP::CLI.new([ fixture("knowledge") ], out: StringIO.new, stdout: StringIO.new)

    assert_equal 0, cli.run
  ensure
    $stdin = was
  end

  private

  # The CLI in-process, as the kernel's suite drives its own: captured streams,
  # returned status. Nothing here exits — the kernel's exe/okf does that, with
  # the status the verb hands back.
  def run_cli(*argv)
    status = nil
    out, err = capture_io { status = OKF::MCP::CLI.run(argv, out: $stderr) }
    Result.new(status, out, err)
  end
end

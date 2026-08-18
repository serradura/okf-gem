# frozen_string_literal: true

require "socket"
require "stringio"
require "webrick"

require_relative "server"

module OKF
  module MCP
    # Bridges the SDK's StreamableHTTPTransport — a plain Rack app — onto the
    # WEBrick that okf already depends on, mirroring the kernel's
    # server/runner pattern (rack and webrick both arrive via the okf gem).
    # Stateless JSON mode: every POST is a self-contained JSON-RPC exchange
    # answered with a single JSON object, so plain buffered responses hold —
    # no SSE stream to keep open. The SDK validates Host/Origin against DNS
    # rebinding for locally bound servers.
    module HTTP
      module_function

      # The Hosts the SDK's StreamableHTTPTransport admits without any extra
      # allowlist — its DNS-rebinding protection accepts these out of the box.
      LOOPBACK_HOSTS = %w[127.0.0.1 ::1 localhost].freeze

      # Binds that mean "every interface" rather than one address.
      WILDCARD_BINDS = %w[0.0.0.0 :: *].freeze

      # The largest request body the bridge will hand the transport, matching
      # the SDK's own StreamableHTTPTransport default. Anything past it is 413
      # before it is allocated (see #read_body).
      MAX_REQUEST_BYTES = 4 * 1024 * 1024

      # Cap on concurrent `subscriptions/listen` streams, far below the SDK's
      # 1000 default because the costs differ in kind: under a Rack 3 server a
      # stream holds no thread, but on this bridge each one parks a WEBrick
      # handler thread *and* occupies one of WEBrick's 100 connection tokens —
      # at the SDK default the tokens exhaust at 100 and every tool call
      # queues behind held streams. 32 leaves two-thirds of the tokens for
      # request traffic. A constant, not a flag: zero-config is this mode's
      # posture, and an operator who needs more has the Rack seam.
      MAX_LISTEN_STREAMS = 32

      # What the SDK writes SSE frames to, adapting its stream contract to
      # WEBrick's proc-body one. The SDK expects write/flush per frame, EPIPE
      # out of write to mean the peer is gone, and close to end the stream;
      # WEBrick ends the response when the body proc returns. So the proc
      # parks in #wait until the SDK — its keepalive thread on a dead peer, or
      # the transport's own close — calls #close, and only then hands the
      # thread back (see #stream_response).
      class Stream
        def initialize(wire)
          @wire = wire
          @lock = Mutex.new
          @done = ConditionVariable.new
          @closed = false
        end

        # One frame, one chunk. A dead peer raises EPIPE/ECONNRESET straight
        # out of the socket write — exactly the signal the SDK's stream
        # cleanup keys on, so it must never be swallowed here.
        def write(data)
          @lock.synchronize do
            raise IOError, "stream is closed" if @closed

            @wire.write(data)
          end
        end

        # WEBrick's ChunkedWrapper has no flush; each write already reaches
        # the socket as a complete chunk.
        def flush
          @wire.flush if @wire.respond_to?(:flush)
          nil
        end

        def close
          @lock.synchronize do
            @closed = true
            @done.broadcast
          end
        end

        def wait
          @lock.synchronize { @done.wait(@lock) until @closed }
        end
      end

      # Everything before accepting — the bind (where EADDRINUSE, the boot
      # failure that actually happens, raises), the traps and the boot line —
      # split from #start so the CLI can run this under its *boot* rescue and
      # file a bind failure as the usage error it is, while a mid-serve errno
      # out of #start stays the crash it is.
      def prepare(server, bind:, port:, allow_hosts: [], out: $stderr)
        app = app_for(server, bind: bind, allowed_hosts: allowed_hosts_for(bind, extra: allow_hosts))
        httpd = build(app, bind: bind, port: port)
        # The trap spawns a thread because #stop takes the transport's mutex,
        # and a mutex inside trap context is ThreadError on Ruby 2.7. A
        # repeated signal just re-runs an idempotent #stop — which is also the
        # honest answer to the narrow race where a listen stream registers
        # concurrently with the close and is only swept by the second pass.
        %w[INT TERM].each { |signal| trap(signal) { Thread.new { stop(httpd, app) } } }
        announce(httpd, bind: bind, out: out)
        httpd
      end

      # Teardown in the only order that terminates: the transport first, so
      # every open listen stream is closed and its parked handler thread
      # returns (see #stream_response) — WEBrick's own shutdown *joins* the
      # connection threads, so closing it first would hang on any open stream.
      def stop(httpd, app)
        app.close
        httpd.shutdown
      end

      # The SDK transport wired to the server, in stateless JSON mode. A
      # non-loopback bind (e.g. 0.0.0.0) is refused by the SDK's DNS-rebinding
      # guard unless its Host is allowlisted; loopback binds keep the SDK
      # defaults. Protection itself stays on either way.
      # +listen_options+ passes `max_listen_subscriptions:` /
      # `listen_keepalive_interval:` through to the SDK — real configuration
      # for a caller composing the bridge directly; the CLI keeps the
      # defaults above.
      def app_for(server, bind:, allowed_hosts: allowed_hosts_for(bind), **listen_options)
        options = { stateless: true, enable_json_response: true, max_request_bytes: MAX_REQUEST_BYTES,
                    max_listen_subscriptions: MAX_LISTEN_STREAMS }.merge(listen_options)
        options[:allowed_hosts] = allowed_hosts if allowed_hosts && !allowed_hosts.empty?
        app = ::MCP::Server::Transports::StreamableHTTPTransport.new(server, **options)
        server.transport = app
        app
      end

      # The Host allowlist a bind address needs: nil for loopback, which the
      # SDK already admits.
      #
      # A **wildcard** bind is the case that was broken. `--bind 0.0.0.0` says
      # "serve every interface", and allowlisting the literal string "0.0.0.0"
      # allowlists a Host header no client ever sends: the server bound
      # everything and answered every real request with 403. What a client
      # actually sends is the address it dialled, so a wildcard expands to this
      # machine's own addresses plus its hostname.
      #
      # +extra+ (the repeatable --allow-host) covers what cannot be derived: a
      # DNS name or a reverse proxy's Host, which no local interface knows.
      # The boot line, plus what a non-loopback bind actually means.
      #
      # The Host allowlist below is a defence against **DNS rebinding** — a
      # browser walked into this port by a page the reader never meant to give
      # it to. It is not access control and must never be sold as one: a client
      # that is not a browser sets `Host` to whatever it likes, and there is no
      # authentication behind it. So binding anywhere but loopback publishes
      # every served bundle to anything that can reach the port, and the boot
      # line says so rather than reading like a URL somebody can safely share.
      #
      # Loopback stays quiet: it is the default and the posture the tool was
      # built for, and a warning printed every time is a warning nobody reads.
      def announce(httpd, bind:, out:)
        # The listener's own port, not the asked-for one: with --port 0 the OS
        # picks, and a boot line reporting 0 would name a port nothing answers.
        bound = httpd.listeners.first.addr[1]
        say(out, "okf-mcp listening on http://#{bind}:#{bound}")
        return if LOOPBACK_HOSTS.include?(bind.to_s)

        say(out, "okf-mcp: WARNING — #{bind} is not loopback. Every served bundle is")
        say(out, "  readable by anything that can reach this port, with no authentication. The Host")
        say(out, "  allowlist only stops browser DNS rebinding; it is not access control.")
      end

      # The boot line is diagnostics, and diagnostics are best-effort: stderr
      # belongs to whoever spawned the process, and a collector that died must
      # not take a bound, healthy server down with it. An EPIPE here is lost
      # output, not a lost server.
      def say(out, line)
        out.puts(line)
      rescue Errno::EPIPE, Errno::ECONNRESET
        nil
      end

      def allowed_hosts_for(bind, extra: [])
        extra = Array(extra).reject { |host| OKF.blank?(host) }
        return (extra.empty? ? nil : extra) if LOOPBACK_HOSTS.include?(bind)

        hosts = WILDCARD_BINDS.include?(bind.to_s) ? local_hosts : [ bind ]
        (hosts + extra).uniq
      end

      # Every address this machine answers on, plus its hostname. Loopback is
      # left out only because the SDK admits it already.
      def local_hosts
        addresses = Socket.ip_address_list.reject(&:ipv4_loopback?).reject(&:ipv6_loopback?)
        names = addresses.map(&:ip_address)
        names << Socket.gethostname.to_s
        names.reject { |name| OKF.blank?(name) }.uniq
      rescue SocketError, SystemCallError
        []
      end

      # Returns an unstarted server so tests can drive an ephemeral port.
      def build(app, bind:, port:)
        httpd = WEBrick::HTTPServer.new(
          BindAddress: bind,
          Port: port,
          Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
          AccessLog: []
        )
        httpd.mount_proc("/") { |request, response| handle(app, request, response) }
        httpd
      end

      def handle(app, request, response)
        # The MCP endpoint is the root and nothing else. The SDK transport
        # routes on method alone, so handing it every path answered the OAuth
        # discovery probes a connecting host sends first (GET /.well-known/*,
        # POST /register — Claude Desktop does) with a 405 and a 200-wrapped
        # JSON-RPC parse error: a *broken* sign-in service instead of an
        # absent one, and the host refused the connector on it. 404 is the
        # answer that reads as absence.
        return not_found(response) unless request.path == "/"

        # The cap is enforced *here*, before the body is materialized. The SDK
        # transport has its own `max_request_bytes` and never reads more than
        # that off `rack.input` — but WEBrick's `request.body` has no limit, so
        # handing the transport a StringIO of it meant the allocation the cap
        # exists to prevent had already happened. A few concurrent 2 GB POSTs
        # would OOM the warm shared process that `--http` exists to provide.
        body = read_body(request)
        return oversized(response) if body.nil?

        status, headers, out = app.call(env_for(request, body))
        response.status = status
        headers.each { |name, value| response[name] = value }
        # A callable body is the Rack 3 streaming shape — the SDK's
        # `subscriptions/listen` answers with one — and buffering it here
        # would block forever on a stream that only ends when the peer goes.
        if out.respond_to?(:call)
          stream_response(response, out)
        else
          buffer = String.new
          out.each { |chunk| buffer << chunk }
          response.body = buffer
        end
      ensure
        out.close if out.respond_to?(:close)
      end

      # Serves a Rack streaming body through WEBrick's proc-body path: with
      # `chunked = true`, WEBrick calls the proc with a ChunkedWrapper after
      # the headers are out, and finalizes the response when it returns. The
      # SDK's callable returns immediately (it registers the stream, writes
      # the acknowledgement, and starts its keepalive thread), so the proc
      # parks this handler thread in Stream#wait until the SDK ends the
      # stream — a dead peer's EPIPE out of a keepalive write, or the
      # transport's close on shutdown.
      def stream_response(response, body)
        response.keep_alive = false # an SSE stream ends with its connection
        response.chunked = true
        response.body = lambda do |wire|
          stream = Stream.new(wire)
          begin
            body.call(stream)
            stream.wait
          ensure
            stream.close # idempotent; covers a body that raised
          end
        end
      end

      # The request body, or nil when it exceeds MAX_REQUEST_BYTES. A declared
      # Content-Length past the cap is refused without reading a byte; an
      # undeclared (chunked) body is streamed and abandoned the moment it grows
      # past it.
      def read_body(request)
        # The raw header, not WEBrick's #content_length: that helper is
        # `Integer(self["content-length"])`, which raises TypeError on a
        # chunked request that legitimately carries no Content-Length at all.
        declared = request["content-length"]
        return nil if declared && declared.to_i > MAX_REQUEST_BYTES

        # Always the block form: `request.body` with no block materializes the
        # whole entity body, which for an undeclared (chunked) request is the
        # very allocation this method exists to bound. With a block WEBrick
        # streams, and a request carrying no body simply never yields.
        buffer = String.new
        request.body do |chunk|
          buffer << chunk
          return nil if buffer.bytesize > MAX_REQUEST_BYTES
        end
        buffer
      end

      def not_found(response)
        response.status = 404
        response["Content-Type"] = "application/json"
        response.body = JSON.generate(error: "not found: the MCP endpoint is /")
      end

      def oversized(response)
        response.status = 413
        response["Content-Type"] = "application/json"
        response.body = JSON.generate(
          jsonrpc: "2.0", id: nil,
          error: { code: -32_600, message: "Request body exceeds #{MAX_REQUEST_BYTES} bytes" }
        )
      end

      def env_for(request, body = request.body.to_s)
        env = {
          "REQUEST_METHOD" => request.request_method,
          "SCRIPT_NAME" => "",
          "PATH_INFO" => request.path,
          "QUERY_STRING" => request.query_string.to_s,
          "SERVER_NAME" => request.host.to_s,
          "SERVER_PORT" => request.port.to_s,
          "rack.url_scheme" => "http",
          "rack.input" => StringIO.new(body.to_s),
          "rack.errors" => $stderr
        }
        request.each do |name, value|
          key = name.upcase.tr("-", "_")
          key = "HTTP_#{key}" unless %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
          env[key] = value
        end
        env
      end
    end
  end
end

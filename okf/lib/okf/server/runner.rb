# frozen_string_literal: true

require "stringio"
require "webrick"

module OKF
  module Server
    # Runs a Rack app under WEBrick — the handful of lines a rackup dependency
    # would otherwise bring in. WEBrick ships with Ruby up to 2.7 and as the
    # `webrick` gem from 3.0 on; both work here, so the gem's server mode keeps
    # rack's own Ruby support range (>= 2.4).
    #
    # The env it builds covers what a GET-serving Rack app needs (method, path,
    # query, headers, rack.input); it is not a general CGI bridge. Part of the
    # shell — it opens sockets.
    module Runner
      module_function

      # Serve +app+ until interrupted (INT/TERM shut the server down).
      def run(app, host:, port:)
        server = build(app, host: host, port: port)
        %w[INT TERM].each { |signal| trap(signal) { server.shutdown } }
        server.start
      end

      # A configured-but-not-started WEBrick server, so callers (and tests) can
      # pick the port (0 = ephemeral), start it on their own thread, and shut it
      # down deterministically.
      def build(app, host:, port:)
        server = WEBrick::HTTPServer.new(
          BindAddress: host, Port: port,
          Logger: WEBrick::Log.new(nil, WEBrick::BasicLog::WARN), AccessLog: []
        )
        server.mount_proc("/") { |request, response| handle(app, request, response) }
        server
      end

      def handle(app, request, response)
        status, headers, body = app.call(env_for(request))
        response.status = status.to_i
        headers.each { |name, value| response[name] = value }
        payload = String.new
        body.each { |chunk| payload << chunk } # a Rack body only guarantees #each
        response.body = payload
      ensure
        body.close if body.respond_to?(:close)
      end

      def env_for(request)
        env = {
          "REQUEST_METHOD" => request.request_method,
          "SCRIPT_NAME" => "",
          "PATH_INFO" => request.path,
          "QUERY_STRING" => request.query_string.to_s,
          "SERVER_NAME" => request.host.to_s,
          "SERVER_PORT" => request.port.to_s,
          "SERVER_PROTOCOL" => "HTTP/#{request.http_version}",
          "rack.url_scheme" => "http",
          "rack.input" => StringIO.new(read_body(request)),
          "rack.errors" => $stderr
        }
        request.each { |name, value| env["HTTP_#{name.upcase.tr("-", "_")}"] = value }
        # Rack reads the entity headers unprefixed.
        env["CONTENT_TYPE"] = env.delete("HTTP_CONTENT_TYPE") if env.key?("HTTP_CONTENT_TYPE")
        env["CONTENT_LENGTH"] = env.delete("HTTP_CONTENT_LENGTH") if env.key?("HTTP_CONTENT_LENGTH")
        env
      end

      # The request body as a string; bodyless requests (every GET this server
      # sees) read as "".
      def read_body(request)
        request.body.to_s
      rescue WEBrick::HTTPStatus::Status, StandardError
        ""
      end
    end
  end
end

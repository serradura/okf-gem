# frozen_string_literal: true

module OKF
  class CLI
    # Boot the graph server. One verb covers three intentions and the argument
    # count is the whole interface: one dir serves it at /, several serve them
    # behind a hub, none serves the registry. Passing dirs never registers them.
    class Server < Command
      def self.id
        :server
      end

      def self.group
        :act
      end

      def self.help_rows
        [
          [ "server    [DIR|@slug…] [-p PORT] [--bind ADDR] [...]", "serve one bundle, or many behind a hub" ]
        ]
      end

      def call(argv)
        require "okf/server/app"
        require "rack/deflater"

        options = { port: 8808, bind: "127.0.0.1", title: nil, link: nil, layout: "cose", allow_manage: false }
        parser = OptionParser.new do |o|
          o.banner = "Usage: okf server [DIR|@slug…] [-p PORT] [--bind ADDR] [--layout NAME] [-t title] [-l url]"
          o.on("-p", "--port PORT", Integer, "port to serve on (default #{options[:port]})") { |v| options[:port] = v }
          o.on("--bind ADDR", "address to bind (default #{options[:bind]})") { |v| options[:bind] = v }
          o.on("-t", "--title TITLE", "graph title, single bundle only (default: parent/bundle dir name)") { |v| options[:title] = v }
          o.on("-l", "--link URL", "source URL shown in the header, single bundle only") { |v| options[:link] = v }
          o.on("--layout NAME", OKF::Render::Graph::LAYOUTS, "initial layout (#{OKF::Render::Graph::LAYOUTS.join(", ")})") { |v| options[:layout] = v }
          o.on("--allow-manage", "manage the registry from the browser on a non-loopback bind") { options[:allow_manage] = true }
          help_flag(o)
        end
        dirs = positional_dirs(parser, argv) or return 2

        # A flag that will have no effect in this mode gets a note, not silence.
        @err.puts "note: --title/--link apply to a single-bundle server; ignored" if dirs.size != 1 && (options[:title] || options[:link])

        # One dir keeps the historical single-bundle server at `/`; zero (the
        # persistent registry) or many (ephemeral) fan out behind a hub.
        if dirs.size == 1
          folder = OKF::Bundle::Folder.load(dirs.first)
          report_skipped(folder)
          run_server(folder, options)
        else
          run_hub(dirs, options)
        end
        0
      rescue OKF::Error => e
        usage_error(e.message)
      end

      private

      # Build the single-bundle Rack app and hand it to the runner (WEBrick by
      # default, injected so tests drive this without a socket).
      def run_server(folder, options)
        app = OKF::Server::App.new(folder, title: options[:title] || folder.name, link: options[:link], layout: options[:layout])
        # minimal: the banner wants a count, not bodies — and Folder#graph is not
        # memoized, so a full build here parses every concept a second time (the
        # App builds its own) purely to print one number.
        count = folder.graph(minimal: true).nodes.size
        @out.puts "serving #{count} #{pluralize(count, "concept")} at http://#{options[:bind]}:#{options[:port]} (Ctrl-C to stop)"
        serve(app, options)
      end

      # Build the multi-bundle hub and hand it to the runner. With dirs it serves
      # those ephemerally; with none it serves the persistent registry. Either way
      # the first bundle is the one `/` opens — for the registry that is its own
      # order, and a first entry whose directory has vanished drops out here, so
      # `/` lands on the next one that is actually there.
      def run_hub(dirs, options)
        require "okf/server/hub"
        require "okf/registry"
        reg = nil
        if dirs.empty?
          # A malformed registry raises OKF::Error, which `server` rescues into a
          # usage error — no guarded load needed on this path.
          reg = OKF::Registry.load
          # The hub's own loader, so the set it rebuilds after a browser-side
          # write is built exactly the way this one was.
          bundles = OKF::Server::Hub.bundles_for(reg) { |entry| skip_registered(entry) }
          bundles.each { |bundle| report_skipped(bundle.folder) }
        else
          bundles = ephemeral_bundles(dirs)
        end
        # The hub keeps the registry so its /b/ manager can report on entries it
        # could not host — a folder deleted out from under one is the question
        # "where did my bundle go?", and only the registry can answer it.
        hub = OKF::Server::Hub.new(bundles, layout: options[:layout], registry: reg, writable: writable?(options))
        concepts = bundles.inject(0) { |sum, bundle| sum + bundle.folder.graph(minimal: true).nodes.size }
        @out.puts "serving #{bundles.size} #{pluralize(bundles.size,
          "bundle")}, #{concepts} #{pluralize(concepts, "concept")} at http://#{options[:bind]}:#{options[:port]} (Ctrl-C to stop)"
        print_mounts(hub)
        serve(hub, options)
      end

      # The one boot seam every served app passes through, so a hub gzips exactly
      # like a single bundle — the wrap belongs to booting a server, not to either
      # mode, and a mode added later gets it for free. Deliberately not inside the
      # runner: an embedding app mounting OKF::Server::App brings its own middleware.
      def serve(app, options)
        # gzip responses when the client accepts it — transparent, no new dependency
        @runner.call(Rack::Deflater.new(app), options[:bind], options[:port])
      end

      # The mount table — which dir landed on which /b/<slug>/ and where `/` goes.
      # Mirrors the Hub's own default resolution (explicit slug, else first).
      # Ask the hub which bundle it chose rather than re-deriving the
      # explicit-else-first rule, and mount at its own prefix: two copies of a
      # rule is two answers waiting to disagree.
      def print_mounts(hub)
        hub.bundles.each do |bundle|
          marker = bundle.equal?(hub.default) ? "*" : " "
          @out.puts "  #{marker} #{OKF::Server::Hub::MOUNT}/#{bundle.slug}/  #{bundle.title}"
        end
      end

      # Load the given directories as unregistered bundles, slugged by basename and
      # deduped within the run. The same directory listed twice mounts once — two
      # windows on one bundle would just burn a slug on a URL that vanishes next run.
      def ephemeral_bundles(dirs)
        roots = []
        dirs.each do |dir|
          root = File.expand_path(dir)
          roots << root unless roots.include?(root)
        end

        # A registered slug owns its mount outright: reserve every ref's slug
        # before any basename is deduped. Otherwise argv order decides, and
        # `server ./two @two` mounts the *unregistered* ./two at /b/two/ while
        # pushing the ref — the bundle whose slug that is — to /b/two-2/, so a
        # bookmark from a bundle-less run silently opens the wrong graph.
        taken = roots.map { |root| ref_slugs[root] }.compact
        roots.each_with_object([]) do |root, bundles|
          folder = OKF::Bundle::Folder.load(root)
          report_skipped(folder)
          slug = ref_slugs[root]
          unless slug
            slug = OKF::Registry.dedupe(File.basename(root), taken)
            taken << slug
          end
          bundles << OKF::Server::Hub::Bundle.new(slug, folder, folder.name)
        end
      end

      # May the browser change the registry? On a loopback bind, yes: the server
      # is reachable only from this machine, and the audience this was built for
      # should not need a flag to use the page they were pointed at. Anywhere
      # else it takes --allow-manage, because `--bind 0.0.0.0` is how a personal
      # tool becomes a public one and a write surface must not follow it there by
      # accident. 0.0.0.0 is *not* loopback — it is every interface, which is the
      # exact case this guards.
      #
      # The flag is named for what it permits, and *manage* is the whole of it:
      # adding, renaming, removing and re-defaulting registry entries, which are
      # references. Nothing here makes a reader's markdown writable from a
      # browser, and "allow edit" was a name that invited exactly that fear.
      def writable?(options)
        options[:allow_manage] || loopback?(options[:bind])
      end

      def loopback?(bind)
        address = bind.to_s
        address == "localhost" || address == "::1" || address.start_with?("127.")
      end
    end

    register(Server)
  end
end

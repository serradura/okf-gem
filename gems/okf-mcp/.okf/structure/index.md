# Structure

Every file under `lib/`, grouped by the layer that owns it. One concept owns
each file, and `test/unit/bundle_catalog_test.rb` fails if that stops being
true in either direction — a file no concept names, or a concept naming a file
that is gone.

Read them bottom-up: each layer depends only on the one below it.

* [The doors](doors.md) - `lib/okf/mcp.rb`, `lib/okf/plugin.rb`, `lib/okf/mcp/cli.rb`, `lib/okf/mcp/app.rb`, `lib/okf/mcp/version.rb` — the three ways in, and the load contract that keeps a bare require cheap.
* [The served set](served-set.md) - `lib/okf/mcp/registry.rb`, `filters.rb`, `backend.rb`, `memory_backend.rb` — which bundles exist, and the cache in front of them.
* [The server definition](server-definition.md) - `lib/okf/mcp/server.rb`, `output_schemas.rb`, `resources.rb` — the fourteen tools, their declared shapes, and concepts as resources.
* [The HTTP bridge](http-bridge.md) - `lib/okf/mcp/http.rb` — WEBrick to Rack, and the streaming adapter that the rest of the gem does not need to know about.

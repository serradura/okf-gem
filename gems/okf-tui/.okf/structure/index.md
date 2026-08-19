# Structure

Every file under `lib/`, grouped by the layer that owns it. One concept owns
each file, and `test/unit/bundle_catalog_test.rb` fails if that stops being true
in either direction — a file no concept names, or a concept naming a file that
is gone.

Ten files, four layers, and the dependency runs one way: the doors build a
workspace, the workspace answers questions about bundles, the app holds the
state and the key loop, and the rendering layer turns that state into rows.
Nothing below reaches back up.

* [The Doors](doors.md) - `lib/okf/tui.rb`, `lib/okf/plugin.rb`, `lib/okf/tui/cli.rb`, `lib/okf/tui/refs.rb`, `lib/okf/tui/version.rb` — the one entry point, the argv shell, and the ref grammar borrowed rather than rewritten.
* [The Workspace and the Model](the-workspace.md) - `lib/okf/tui/workspace.rb`, `lib/okf/tui/model.rb` — which bundles a session can see, and every answer about one of them.
* [The App](the-app.md) - `lib/okf/tui/app.rb` — state, the key loop, and the frame.
* [The Rendering Layer](rendering.md) - `lib/okf/tui/views.rb`, `lib/okf/tui/ui.rb` — the six screens as row builders, and the primitives that make a row fit.

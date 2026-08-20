---
type: Component
title: The HTTP bridge
description: WEBrick to Rack in one file — buffered responses, the streaming adapter that parks a handler thread until the SDK ends a stream, and the teardown order that stops it hanging.
tags: [mcp, http, webrick, streaming, teardown]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/mcp/http.rb
---

# The file

| file | what it owns |
| ---- | ------------ |
| `lib/okf/mcp/http.rb` | `OKF::MCP::HTTP` — `prepare`, `stop`, `app_for`, `build`, `handle`, and the two stream classes `Stream` and `Streams` |

This is the only file that knows WEBrick exists. `--http` goes through it;
`OKF::MCP.app` under a Rack 3 server does not, which is why the streaming
subtleties below are scoped to this bridge and not to the gem.

# The subtlety the whole file is shaped around

`subscriptions/listen` is answered by the SDK with a **Rack streaming body
whose callable returns immediately**. WEBrick ends a proc-body response when
the proc returns. Composed naively, every listen would close the instant it
opened.

So `Stream#wait` parks the handler thread until the SDK ends the stream, and
`Streams` is the bounded set of live ones. Three consequences are load-bearing,
and `test/integration/http_listen_test.rb` pins each:

- **Teardown closes the transport before WEBrick.** `HTTP.stop` does them in
  that order because WEBrick's shutdown joins its connection threads and hangs
  on any open stream.
- **The signal trap hands teardown to a thread.** A mutex in trap context is a
  `ThreadError` on 2.7, which is the floor.
- **Listens are capped at 32, on this bridge only.** Each holds a WEBrick
  thread and a connection token. That is not true under a Rack server, where
  the SDK's own default stands, so the cap belongs here rather than in the
  server definition.

**`EPIPE` must propagate.** A dead peer is noticed by `EPIPE` raising out of a
keepalive write, and that propagation *is* the SDK's cleanup signal. An adapter
that rescues it leaks the stream instead of closing it — so the rescue that
looks defensive is the bug.

# Host and origin checking

`allowed_hosts_for` and `local_hosts` derive the default allowlist from the
bind address. `app_for` is where `allowed_hosts` and `allowed_origins` reach
the transport, and it is called from [`App`](doors.md) rather than duplicated —
one construction site, so a new option cannot land on half the callers.

`read_body` bounds the request body and `oversized` is its refusal;
`not_found` answers anything off the MCP path.

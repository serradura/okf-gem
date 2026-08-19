# Capabilities

What this server offers a host, and what implements each of them. This area is
the catalog an agent reads instead of opening `lib/okf/mcp/server.rb` to find
out whether something already exists.

* [The fourteen tools](tools.md) - Every tool: what it answers, the kernel call behind it, and the CLI verb it is kin to.
* [Resources and prompts](resources-and-prompts.md) - What the protocol offers that a tool does not: bundles and concepts as resources, completions, and the two consuming prompts.
* [Transports](transports.md) - stdio, Streamable HTTP, and any Rack 3 server — one definition behind all three.

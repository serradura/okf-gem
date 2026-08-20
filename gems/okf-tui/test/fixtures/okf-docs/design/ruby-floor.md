---
type: Constraint
title: The Ruby 2.4 floor
description: The gem runs on every Ruby since 2.4 so it works on the interpreter an OS already ships.
tags: [ruby, portability]
timestamp: 2026-07-17T16:00:00Z
---

# Overview

`required_ruby_version >= 2.4.0`. The point is to run on the Ruby an operating
system already ships, without asking anyone to install a newer one — the same
floor as [rack](runtime-dependencies.md), the gem's core dependency. This is why
the gem stays deliberately light.

# The floor bans APIs RuboCop won't catch

RuboCop parses at 2.4 and catches syntax, but **not** newer standard-library
methods, so those are a manual discipline. A non-exhaustive list of what is off
limits:

- **2.5** — `delete_prefix`/`delete_suffix`, `transform_keys`, `Dir.children`,
  `yield_self`;
- **2.6** — `to_h { }`, `then`, endless string slices `str[i..]`, `YAML.safe_load`
  keyword args (allowed **only** inside the
  [Frontmatter shim](../format/frontmatter.md));
- **2.7** — `filter_map`, `tally`, numbered block params;
- **3.x** — endless methods, hash shorthand.

These constraints apply to `test/` too, because the suite runs on 2.4 as well.

# The truth test

"Works on my Ruby" is not verification here. The floor is checked in CI across
every supported Ruby, and locally by copying the tree into a throwaway build dir,
dropping `Gemfile.lock` (the committed lockfile is written by a modern Bundler that
2.4's own cannot read), and mounting the checkout **read-only** so the run cannot
write one back:

```bash
docker run --rm -v "$PWD":/src:ro ruby:2.4 bash -c \
  "cp -a /src /build && cd /build && rm -f Gemfile.lock && bundle install --quiet && bundle exec rake test"
```

# Citations

[1] [okf.gemspec](https://github.com/serradura/okf-gem/blob/main/okf.gemspec) — `required_ruby_version = ">= 2.4.0"`.
[2] [AGENTS.md — Hard constraints](https://github.com/serradura/okf-gem/blob/main/AGENTS.md) — the banned-API list and the Docker truth test.

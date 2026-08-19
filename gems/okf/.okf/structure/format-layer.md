---
type: Component
title: The Format Layer
description: "Pure, and the bottom of everything: path normalisation with a root-escape guard, the one YAML door, and the link and citation grammars §5 and §8 are written in."
tags: [structure, format, pure, yaml, links]
generated:
  by: human:maintainer
  at: 2026-08-19T12:00:00Z
resource: lib/okf/path.rb
---

# The files

| file | what it owns |
|---|---|
| `lib/okf.rb` | `OKF::Error`, `OKF.blank?`, `OKF.iso8601`, `OKF.dir_of`, `SPEC_VERSION` |
| `lib/okf/version.rb` | `OKF::VERSION` |
| `lib/okf/path.rb` | `Path.normalize_relative!`, `join_under!`, `under?` — and `Path::Error` |
| `lib/okf/safe_read.rb` | `SafeRead.contained_path!`, `read!` — containment for a caller that already holds a root |
| `lib/okf/markdown/frontmatter.rb` | parse, dump, `stringify_keys` — **the only** YAML door |
| `lib/okf/markdown/links.rb` | §6: inline, reference and footnote links, and how a raw target resolves |
| `lib/okf/markdown/citations.rb` | §8: the `# Citations` section and its entries |

# Containment is a primitive here, not a habit

`Path.normalize_relative!` rejects any `..` segment outright, which is what makes
"a concept cannot link out of its own bundle" a property of the format rather
than a convention. `join_under!` and `under?` are the two questions every writer
and every reader asks before touching a path, and `SafeRead.read!` is the pair of
them plus the read, for callers that already hold a root — it resolves symlinks
and refuses one that leaves.

Every layer above reaches for these rather than composing its own check. A second
containment implementation is the shape this class of bug takes.

# One YAML door

**All YAML goes through `Markdown::Frontmatter`** — `safe_load`, with `Date` and
`Time` permitted and aliases off. `PSYCH_KEYWORDS` is the Psych < 3.1
positional-argument shim, and it lives here precisely so that
`YAML.safe_load`/`YAML.load` is called in exactly one place in the gem.

`stringify_keys` exists so that ActiveSupport does not, which is the same reason
`OKF.blank?` does.

# The link grammar is where the graph comes from

`Links.extract` walks prose lines only — `FENCE` and `CODE_SPAN` take fenced
blocks and code spans out first, because a link inside a code sample is a
document about a link, not an edge. `INLINE_LINK`, `REFERENCE_LINK` and
`DEFINITION` cover the three markdown spellings; `FOOTNOTE_REFERENCE` and
`FOOTNOTE_DEFINITION` are §8's keying. `SCHEME` and `MAILTO` are what keep an
external URL from being read as a relative path.

What is built on top of these is [the-model](/structure/the-model.md).

`Links.resolve` is the one that turns a raw target into a bundle-relative path,
and it is why a link split across a newline produces no edge — the extractor
reads a line at a time.

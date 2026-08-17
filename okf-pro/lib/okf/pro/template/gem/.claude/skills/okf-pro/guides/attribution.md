# Attributing what you did not write

Everything in `reference/` is somebody else's claim, and the bundle's
whole argument is that a claim can be traced back. That is `sources:` — a
list of what the concept was derived from, each entry with a `resource`
naming something a reader can follow (a URL, a bundle path) or, when there
is nothing to follow, the population it came from (`all invoices in
Q3 2026`).

```yaml
sources:
  - id: acme-pricing
    resource: https://acme.example/pricing
    title: Acme pricing page
    author: team:acme-marketing
    last_modified: 2026-08-01
```

**Attribute individual claims with footnotes keyed to a `sources[].id`**,
not with a citations list at the bottom:

```markdown
Seats are billed annually, with no monthly option.[^acme-pricing]
```

The label *is* the join key — the reader resolves attribution through the
matching entry, and never by parsing the footnote's prose. Keyed rather
than positional because agents rewrite these documents constantly: a
`sources[0]` misattributes silently the moment the list is reordered,
while a stable `id` survives it.

Two lint checks hold this up, and both **block** an edit:

* a footnote whose label matches no `sources[].id` and has no definition
  of its own — the claim points at nothing, which is worse than an
  unattributed claim because it reads as attributed;
* a `sources[].resource` naming a bundle path that does not exist.

Neither fires on a concept with no `sources[].id` at all: a bundle that has
not adopted keyed attribution is not at fault, and an ordinary markdown
footnote is prose. The moment one source carries an `id`, the join is live.

A source with no `id` is fine when nothing in the body cites it
individually — the provenance is still recorded. Give it an `id` when a
sentence needs to point at it.


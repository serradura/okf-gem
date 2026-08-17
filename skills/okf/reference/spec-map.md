# What each SPEC section governs

Kind: index. Answers: which § of the vendored spec settles a question, so you
consult one section instead of re-reading all of [SPEC.md](SPEC.md).

The spec is vendored **verbatim** from upstream — its header names the commit
and the licence — so it is never edited here and never split; this file is its
map, kept beside it. The § numbers are the stable keys: cite `§6.2`, never a
heading or a line number. Every section is here, including the two an authoring
question rarely reaches: an index that quietly drops what it judges uninteresting
misroutes the reader who wanted exactly that. <!-- rule:okf-spec-map -->

| § | Governs | Reach for it when |
|---|---------|-------------------|
| §1 | motivation, goals, and the **non-goals** | arguing why OKF at all; checking a proposal against what the format refuses to be |
| §2 | terminology — bundle, concept, concept ID, frontmatter, body, link, source, provenance, credibility signal, actor, trust tier, attested computation, executor, receipt, attester | a word is load-bearing in a disagreement, or a field name reads two ways |
| §3 | bundle structure, reserved filenames | laying out directories |
| §4 | concept documents & frontmatter | writing or validating a concept |
| §5.1 | provenance — `sources` and its credibility signals | any external or empirical claim |
| §5.2 / §5.3 | trust — `generated`, `verified`, and the derived tiers | recording who wrote or confirmed content |
| §5.4 / §5.5 | lifecycle — `status`, `stale_after` | marking drafts, deprecations, expiries |
| §6 / §6.1 | cross-links; **broken links are tolerated** | linking; judging a "broken" link |
| §6.2 / §6.3 | path-valued fields; the `references/` convention | pointing at non-concept assets |
| §7 | the actor convention | filling any `by` |
| §8 | index files & progressive disclosure | orienting; writing or synthesizing an index |
| §9 | log files | recording history |
| §10 | attested computations | a concept that *is* a sanctioned computation |
| §11 | conformance — the hard gate | what `validate` may and may not reject |
| §12 | versioning (`okf_version`) | the root index's one allowed field |
| §13 | changes from v0.1 | migrating a bundle; reading an unmigrated one |
| Appendix A | one worked bundle exercising every family, as a v0.1 → v0.2 migration | you want the whole shape at once rather than a rule at a time |


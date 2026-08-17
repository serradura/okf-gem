# No tooling required

Kind: principle. Answers: what formats are allowed, when a schema or
parser is justified, why plain markdown wins.

If you can cat a file, you can read it. Every structural device in a
skill must survive being read as plain prose by a model with no parser,
because that is exactly how it will be read. <!-- rule: ss-cat-test -->

## Allowed devices

Headings, lists, tables, fenced code blocks, markdown links, and HTML
comments for keys. All of these carry structure and read naturally as
prose. Nothing else is needed.

## Refused devices

* Custom DSLs or schemas the model must be taught to parse.
* Structure that only a build step can produce or verify. A skill that
  needs a compile is a skill that rots the day the tool does.
* Frontmatter keys beyond what the host harness defines. Frontmatter is
  contested space shared with every harness that reads the file; the
  body is not. Express structure in the body and the index, and add a
  frontmatter key only when a machine genuinely must read it, prefixed
  to avoid collisions. <!-- rule: ss-frontmatter-restraint -->

## The test

Hand any single file from the skill to a person with no context and no
tools. If they can tell what it is, what it covers, and where the rules
are, the file passes. If they need the tooling story explained first, it
fails.

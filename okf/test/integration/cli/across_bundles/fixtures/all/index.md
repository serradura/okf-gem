---
okf_version: "0.1"
---

# All

A bundle whose directory name collides with the one slug the ref grammar keeps
for itself: `@all` means every registered bundle, so no single bundle may answer
to it. Registering this directory proves the two paths part company — minting a
slug from the basename suffixes it to `all-2`, while `--as all` is refused
outright, because there the name is the user's and substituting another is the
one thing the slug rules never do.

Nothing here is about @all; the bundle only has to exist, and be somewhere on
disk with a name nobody would otherwise choose.

* [Collision](collision.md) - why the basename cannot become the slug.

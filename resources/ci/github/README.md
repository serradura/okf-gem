# OKF on GitHub Actions

`okf.yml` validates and lints your OKF bundles on every push and pull request.
Copy it into your repository at `.github/workflows/okf.yml` and change one line.

```bash
mkdir -p .github/workflows
curl -o .github/workflows/okf.yml \
  https://raw.githubusercontent.com/serradura/okf-gem/main/resources/ci/github/okf.yml
```

## The one line to change

```yaml
        env:
          # ─── the one repository-specific line ───────────────────────────────
          BUNDLES: ".okf"
```

`BUNDLES` is a space-separated list of bundle paths, relative to the repository
root. One bundle is the common case and the default; a monorepo names each one:

```yaml
          BUNDLES: ".okf docs/.okf packages/api/.okf"
```

Nothing else in the file is repository-specific. This recipe and the workflow
this repository runs against its own bundles are the same file apart from that
single line — that is what keeps the recipe from rotting, since a break in it
is a red check here:

```bash
diff resources/ci/github/okf.yml .github/workflows/okf.yml
# 41c41 — the BUNDLES line, and nothing else
```

## What it runs

Two commands per bundle, and they answer different questions:

| command | asks | fails the job |
|---|---|---|
| `okf validate` | is this a conformant OKF v0.2 bundle? | yes — exit 1 on a hard error |
| `okf lint` | is it well curated? | no — advisory, exit 0 whatever it finds |

`lint` is advisory on purpose: a stub or a loose leaf can be deliberate, and a
curation report that blocks a merge is a report people learn to route around.
Opt into gating when you want it, per level:

```yaml
            docker run --rm -v "$PWD":/data ghcr.io/serradura/okf:latest lint "$bundle" --fail-on warn
```

Both come from `ghcr.io/serradura/okf`, the published image, so the job installs
nothing on the runner — no Ruby, no gem, no bundler cache. Pin a version instead
of `:latest` if you want the job to be reproducible across image releases:

```yaml
            docker run --rm -v "$PWD":/data ghcr.io/serradura/okf:2.1.0 validate "$bundle"
```

## The landmine: do not use `container:`

```yaml
container: ghcr.io/serradura/okf:latest   # ← actions/checkout FAILS here
```

`container:` runs *every* step inside the image, and `actions/checkout` is a
Node action. The image is `ruby:4.0-alpine` and ships no node, so the checkout
fails before any okf command runs. The recipe uses a plain `docker run` against
the mounted checkout instead, which is the shape the image already has
(`WORKDIR /data`, `ENTRYPOINT ["okf"]`).

## Permissions

The image runs as a non-root user (`okf`, uid 1000) while a GitHub runner's
checkout belongs to a different uid. That is fine: checkout writes world-readable
files, and the two okf commands here only read. Verified against a checkout owned
by uid 1001 with `u=rwX,go=rX` — both commands exit 0.

Writing verbs (`okf skill`, `okf pro setup`) are a different matter: uid 1000
cannot create anything under a checkout it does not own, and the command dies
with `Permission denied @ dir_s_mkdir (Errno::EACCES)`. Add
`--user "$(id -u):$(id -g)"` to the `docker run` when a step has to write.

## GitLab, and everything else

There is no `resources/ci/gitlab/` yet, and there will not be one until a file
exists to put in it. The shape is the same three lines — `image:` will not work
for the same reason `container:` does not, so use a `docker run` in a `script:`
against `$CI_PROJECT_DIR`.

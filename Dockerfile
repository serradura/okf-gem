# A portable okf CLI: the whole toolkit (validate, lint, search, index, and the
# live graph server) with no Ruby on the host. See #6.
#
# The build is two stages so the runtime image carries only the installed gem,
# not the checkout or the build toolchain. It builds okf from source in this
# repo (not from RubyGems), so `docker build .` is self-contained and a release
# tag's image always matches that commit's okf/lib/okf/version.rb.
#
# The gem lives in okf/ but the build context stays the repository root: the
# gemspec derives spec.files from `git ls-files`, which needs the .git directory
# that only the root has.

# ---- build stage: turn the checkout into a .gem ----------------------------
FROM ruby:4.0-alpine AS build

# okf.gemspec derives spec.files from `git ls-files`, so the build needs git and
# the .git directory in the context (keep it out of .dockerignore).
RUN apk add --no-cache git

# safe.directory names /src, not /src/okf: the git directory is the repo root.
WORKDIR /src
COPY . .
RUN git config --global --add safe.directory /src \
 && cd okf \
 && gem build okf.gemspec \
 && mv okf-*.gem /tmp/okf.gem

# ---- runtime stage: just the installed CLI ---------------------------------
FROM ruby:4.0-alpine

LABEL org.opencontainers.image.source="https://github.com/serradura/okf-gem" \
      org.opencontainers.image.description="OKF (Open Knowledge Format) toolkit: validate, lint, search, and serve bundles as a live graph." \
      org.opencontainers.image.licenses="Apache-2.0"

COPY --from=build /tmp/okf.gem /tmp/okf.gem
RUN gem install /tmp/okf.gem --no-document \
 && rm -f /tmp/okf.gem \
 && adduser -D -u 1000 okf

USER okf

# The bundle is mounted here, so `okf validate .` works: -v "$PWD:/data"
WORKDIR /data

# `okf server . --bind 0.0.0.0` serves the graph on this port (the CLI default
# 127.0.0.1 is unreachable from outside the container).
EXPOSE 8808

# `docker run IMAGE validate .` mirrors the CLI; bare `docker run IMAGE` prints
# the version.
ENTRYPOINT ["okf"]
CMD ["--version"]

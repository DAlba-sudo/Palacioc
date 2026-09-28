# Build context is the repository root:
#
#   docker build -f dev/Dockerfile -t palacioc-server .
#
# Stages:
#   zig    - Zig toolchain only (used by the `zig` compose service)
#   build  - fetches dependencies and compiles the server
#   (last) - slim runtime image containing just the server binary
#
# Every stage is cached, so once built, source-only changes rebuild just the
# final `zig build` and copy, without needing network access.

FROM debian:stable-slim AS zig

ARG TARGETARCH
ARG ZIG_VERSION="0.16.0"

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  wget \
  xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH}" in \
      arm64) ZIG_ARCH="aarch64" ;; \
      amd64) ZIG_ARCH="x86_64" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    wget -qO /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" && \
    mkdir -p /opt/zig && \
    tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 && \
    rm /tmp/zig.tar.xz && \
    ln -s /opt/zig/zig /usr/local/bin/zig

WORKDIR /app

CMD ["zig", "version"]

FROM zig AS build

# Fetch dependencies in their own layer, keyed only on build.zig.zon, so edits
# to build.zig or src/ reuse the cached dependencies. A stub build.zig is all
# `--fetch` needs; the real one is copied afterwards.
COPY build.zig.zon ./
RUN echo 'pub fn build(_: *@import("std").Build) void {}' > build.zig && \
    zig build --fetch=all

COPY build.zig ./
COPY src/ src/
RUN zig build -Doptimize=ReleaseSafe

FROM debian:stable-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/zig-out/bin/server /usr/local/bin/server

USER nobody

ENTRYPOINT ["server"]

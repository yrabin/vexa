# vexa-devbox — every tool the repo's unit tests and gates need, in one image, so the host
# needs nothing but Docker. The repo itself is NOT baked in: devbox.sh bind-mounts the checkout
# at the same absolute path it has on the host (so `make debug` sibling containers resolve it).
#
#   docker build -t vexa-devbox tools/devkit/devbox        (or: tools/devkit/devbox/devbox.sh build)
# Base images are overridable (e.g. --build-arg NODE_IMAGE=mirror.gcr.io/library/node:22-bookworm
# when Docker Hub rate-limits you).
ARG NODE_IMAGE=node:22-bookworm
ARG DOCKER_CLI_IMAGE=docker:27-cli
ARG UV_IMAGE=ghcr.io/astral-sh/uv:latest
FROM ${DOCKER_CLI_IMAGE} AS dockercli
FROM ${UV_IMAGE} AS uv

FROM ${NODE_IMAGE}

ARG WITH_CLAUDE=1

# Unit tests never launch a real browser (join tests use jsdom fixtures), and CI skips the native
# ONNX download the same way (.github/workflows/gates.yml) — both keep `pnpm install` light.
# The pnpm store lives in the home volume: left to itself, pnpm puts it at the bind mount's root
# (inside your checkout) because the volume is a different filesystem.
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    pnpm_config_store_dir=/root/.pnpm-store \
    ONNXRUNTIME_NODE_INSTALL=skip \
    UV_LINK_MODE=copy \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# node:22-bookworm already ships make, git, curl, ssh and python3; add the two helpers for poking
# the bot's redis command bus and JSON (redis-cli, jq).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      jq redis-tools \
 && rm -rf /var/lib/apt/lists/* \
 && corepack enable \
 && git config --system --add safe.directory '*'

# uv (Python toolchain + test runner for the Python services).
COPY --from=uv /uv /uvx /usr/local/bin/

# Docker CLI + compose plugin only — they talk to the HOST daemon through the mounted socket.
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

# Claude Code CLI (optional): its login lives in the devbox home volume, never on the host.
RUN if [ "$WITH_CLAUDE" = "1" ]; then npm install -g @anthropic-ai/claude-code && npm cache clean --force; fi

WORKDIR /root
CMD ["bash"]

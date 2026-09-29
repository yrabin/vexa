#!/usr/bin/env bash
# devbox.sh — run the repo's tooling inside the vexa-devbox container; the host needs only Docker.
# Works with macOS's stock bash 3.2 (no bash-4 features). See README.md next to this file.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"          # the checkout, mounted at the SAME path inside
IMAGE="${DEVBOX_IMAGE:-vexa-devbox}"
HOME_VOLUME="${DEVBOX_HOME_VOLUME:-vexa-devbox-home}"   # pnpm/uv caches, git + Claude login
# Extra `docker run` flags, word-split on spaces, e.g. DEVBOX_DOCKER_ARGS="-p 8000:8000 -e FOO=1"
EXTRA_ARGS="${DEVBOX_DOCKER_ARGS:-}"

usage() {
  cat <<EOF
Usage: tools/devkit/devbox/devbox.sh <command> [args]

  build              build the devbox image ($IMAGE)
  shell              interactive shell in the repo (git, pnpm, uv, make, docker, claude)
  run <cmd...>       run one command in the repo, e.g. run git status
  install            pnpm install (first time, and after pulling dependency changes)
  test <suite>       run a unit-test suite:
                       join         @vexa/join (join flows vs saved HTML, no browser)
                       bot          @vexa/bot  (orchestrator + adapters with fake ports)
                       node         every Node package (turbo run test)
                       meeting-api  core/meetings/services/meeting-api (pytest)
                       agent        core/agent (pytest: control plane, worker, llm)
                       agent-api    core/agent/services/agent-api (pytest)
                       runtime      core/runtime (pytest; one test runs a real alpine container)
                       gates        the fast static gates (exactly what the pre-push hook runs)
  join-debug <url>   watch the join layer drive a real meeting (noVNC on http://localhost:6080)
  claude             start Claude Code in the repo (login is kept in the home volume)
  forget             delete the home volume (caches, git credentials, Claude login)
EOF
}

devbox_run() {
  local tty=()
  [ -t 0 ] && [ -t 1 ] && tty=(-it)
  local sock=()
  [ -S /var/run/docker.sock ] && sock=(-v /var/run/docker.sock:/var/run/docker.sock)
  docker run --rm --init ${tty[@]+"${tty[@]}"} \
    -v "$ROOT":"$ROOT" -w "$ROOT" \
    -v "$HOME_VOLUME":/root \
    ${sock[@]+"${sock[@]}"} \
    $EXTRA_ARGS \
    "$IMAGE" "$@"
}

ensure_image() {
  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "→ $IMAGE not built yet; building it first"
    docker build -t "$IMAGE" "$HERE"
  fi
}

cmd="${1:-help}"
[ $# -gt 0 ] && shift

case "$cmd" in
  build)
    docker build -t "$IMAGE" "$@" "$HERE" ;;
  shell)
    ensure_image; devbox_run bash ;;
  run)
    [ $# -gt 0 ] || { echo "run needs a command" >&2; exit 2; }
    ensure_image; devbox_run "$@" ;;
  install)
    ensure_image; devbox_run pnpm install --frozen-lockfile ;;
  test)
    suite="${1:-}"
    ensure_image
    case "$suite" in
      join)        devbox_run pnpm exec turbo run test --filter=@vexa/join ;;
      bot)         devbox_run bash -c 'pnpm exec turbo run build && pnpm --filter @vexa/bot test' ;;
      node)        devbox_run pnpm test ;;
      meeting-api) devbox_run bash -c 'cd core/meetings/services/meeting-api && uv run pytest -q' ;;
      agent)       devbox_run bash -c 'cd core/agent && uv run pytest -q' ;;
      agent-api)   devbox_run bash -c 'cd core/agent/services/agent-api && uv run pytest -q' ;;
      runtime)     devbox_run bash -c 'cd core/runtime && uv run pytest -q' ;;
      gates)       devbox_run sh .githooks/pre-push ;;
      *) echo "unknown suite '${suite}'" >&2; usage; exit 2 ;;
    esac ;;
  join-debug)
    [ $# -gt 0 ] || { echo "join-debug needs a meeting URL" >&2; exit 2; }
    ensure_image
    devbox_run make -C core/meetings/modules/join debug URL="$1" ;;
  claude)
    ensure_image; devbox_run claude "$@" ;;
  forget)
    docker volume rm "$HOME_VOLUME" ;;
  help|-h|--help)
    usage ;;
  *)
    echo "unknown command '$cmd'" >&2; usage; exit 2 ;;
esac

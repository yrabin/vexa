#!/usr/bin/env bash
# deploy.sh — run ON THE SERVER (as user dev). Syncs the checkout to a branch and (re)starts Vexa.
#
#   deploy.sh all  [branch]   full Compose stack from the PUBLISHED images (baseline; no build)
#   deploy.sh dev  [branch]   build the bot + the whole stack FROM YOUR BRANCH, then start it
#   deploy.sh bot  [branch]   rebuild only the bot image (next bot uses it; stack keeps running)
#   deploy.sh lite [branch]   single-container Vexa Lite (+ local CPU speech-to-text if unconfigured)
#   deploy.sh status | logs | down
#
# Compose (all/dev/bot) reads deploy/compose/.env; Lite reads the repo-root .env. The first run
# creates deploy/compose/.env from .env.example with freshly minted secrets.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/yrabin/vexa.git}"
REPO_DIR="${REPO_DIR:-$HOME/vexa}"
COMPOSE_ENV="$REPO_DIR/deploy/compose/.env"

say() { printf '\n→ %s\n' "$*"; }

sync_repo() {
  local branch="${1:-}"
  if [ ! -d "$REPO_DIR/.git" ]; then
    say "cloning $REPO_URL into $REPO_DIR"
    git clone "$REPO_URL" "$REPO_DIR"
  fi
  cd "$REPO_DIR"
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "✗ $REPO_DIR has uncommitted changes to tracked files — commit/stash them first." >&2
    exit 1
  fi
  git fetch --prune origin
  if [ -n "$branch" ]; then
    say "checking out $branch"
    git checkout -B "$branch" "origin/$branch"
  else
    git pull --ff-only
  fi
  echo "  at $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD): $(git log -1 --format=%s)"
}

set_env() {  # set_env FILE KEY VALUE — replace KEY=… or append it
  local file="$1" key="$2" value="$3"
  if grep -qE "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

get_env() {  # get_env FILE KEY — value with any inline comment stripped
  grep -E "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2- | sed -E 's/[[:space:]]+#.*$//; s/[[:space:]]+$//'
}

ensure_compose_env() {
  if [ -f "$COMPOSE_ENV" ]; then return; fi
  say "creating deploy/compose/.env with fresh secrets"
  cp "$REPO_DIR/deploy/compose/.env.example" "$COMPOSE_ENV"
  local k
  for k in ADMIN_TOKEN INTERNAL_API_SECRET VEXA_DISPATCH_SIGNING_KEY NEXTAUTH_SECRET; do
    set_env "$COMPOSE_ENV" "$k" "$(openssl rand -hex 32)"
  done
  chmod 600 "$COMPOSE_ENV"
  cat <<EOF
  Fill in credentials in $COMPOSE_ENV before sending bots:
    TRANSCRIPTION_SERVICE_URL / TRANSCRIPTION_SERVICE_TOKEN   (speech-to-text; see hetzner/README.md)
    one model credential (ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN, VEXA_LLM_*)  (agent chat)
  then re-run this script.
EOF
}

warn_missing_creds() {
  local f="$1"
  if [ -z "$(get_env "$f" TRANSCRIPTION_SERVICE_URL)" ]; then
    echo "  ⚠ TRANSCRIPTION_SERVICE_URL is empty in $f — bots will join but POST /bots answers 503"
    echo "    unless you send {\"transcribe_enabled\": false}. (Lite: use 'deploy.sh lite' → local STT.)"
  fi
}

mode="${1:-help}"
[ $# -gt 0 ] && shift

case "$mode" in
  all)
    sync_repo "${1:-}"; ensure_compose_env; warn_missing_creds "$COMPOSE_ENV"
    say "starting the full stack from published images (make all)"
    make all ;;
  dev)
    sync_repo "${1:-}"; ensure_compose_env; warn_missing_creds "$COMPOSE_ENV"
    set_env "$COMPOSE_ENV" BROWSER_IMAGE "vexa/vexa-bot:dev"
    say "building the bot from source (make bot → vexa/vexa-bot:dev)"
    make bot
    say "building + starting every service from source (make dev) — first run takes a while"
    make dev ;;
  bot)
    sync_repo "${1:-}"; ensure_compose_env
    set_env "$COMPOSE_ENV" BROWSER_IMAGE "vexa/vexa-bot:dev"
    say "rebuilding only the bot image"
    make bot ;;
  lite)
    sync_repo "${1:-}"
    if [ ! -f "$REPO_DIR/.env" ] && [ -f "$COMPOSE_ENV" ]; then
      echo "  (Lite seeds the repo-root .env from deploy/compose/.env)"
    fi
    if [ -z "$(get_env "$REPO_DIR/.env" TRANSCRIPTION_SERVICE_URL)" ] && [ -z "$(get_env "$COMPOSE_ENV" TRANSCRIPTION_SERVICE_URL)" ]; then
      say "no speech-to-text configured — starting Lite with the bundled CPU Whisper (LOCAL_STT=1)"
      make -C deploy/lite all LOCAL_STT=1
    else
      say "starting Vexa Lite"
      make lite
    fi ;;
  status)
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' ;;
  logs)
    cd "$REPO_DIR" && make -C deploy/compose logs ;;
  down)
    cd "$REPO_DIR"
    make down || true
    make -C deploy/lite down || true ;;
  help|-h|--help)
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)
    echo "unknown mode '$mode'" >&2; sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

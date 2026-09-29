#!/usr/bin/env bash
# tunnel.sh — run ON THE LAPTOP. Forwards the server's Vexa ports to localhost over SSH, so nothing
# but SSH is ever exposed to the internet. Uses macOS's built-in ssh (nothing to install).
#
#   tools/devkit/hetzner/tunnel.sh <server-ip>        (Ctrl-C to close)
#
# Then open:  Compose → http://localhost:13000 (Terminal UI) · http://localhost:18056 (API)
#             Lite    → http://localhost:3001  (Terminal)    · http://localhost:8056  (API)
#             noVNC (join debug / Lite bot view) → http://localhost:6080/vnc.html
set -euo pipefail

HOST="${1:-}"
[ -n "$HOST" ] || { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
USER_NAME="${VEXA_SSH_USER:-dev}"
KEY="${VEXA_SSH_KEY:-$HOME/.ssh/vexa_hetzner}"

key_args=()
[ -f "$KEY" ] && key_args=(-i "$KEY")

forwards=()
for p in 13000 18056 3001 8056 8100 6080; do
  forwards+=(-L "127.0.0.1:${p}:127.0.0.1:${p}")
done

echo "tunnel → ${USER_NAME}@${HOST}  (Compose :13000/:18056 · Lite :3001/:8056 · noVNC :6080) — Ctrl-C to close"
exec ssh -N -o ExitOnForwardFailure=no -o ServerAliveInterval=30 \
  ${key_args[@]+"${key_args[@]}"} "${forwards[@]}" "${USER_NAME}@${HOST}"

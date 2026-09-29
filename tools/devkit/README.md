# tools/devkit — develop on a Docker-only laptop, deploy to a Hetzner server

Dev tooling for this fork (not shipped, not part of any service). It supports one workflow:

```
laptop (VS Code + Docker only)         GitHub (your fork)                 Hetzner server (Ubuntu + Docker)
─────────────────────────────         ──────────────────                 ────────────────────────────────
edit in VS Code                ─push─► branch · PR · CI gates   ◄─pull─── deploy.sh dev <branch>
devbox.sh test / shell / claude                                           real bots in real meetings
                                                                          viewed via tunnel.sh from the laptop
```

| Folder | What it is | Where it runs |
|---|---|---|
| [`devbox/`](devbox/README.md) | A toolbox container (Node 22, pnpm, uv, git, make, Docker CLI, Claude Code) plus `devbox.sh` to run unit tests, git and Claude without installing anything on the host | Laptop |
| [`hetzner/`](hetzner/README.md) | Server bootstrap (`cloud-init.yaml`), the deploy script (`deploy.sh`) and the laptop-side SSH tunnel (`tunnel.sh`) | Server + laptop |

Start with [`devbox/README.md`](devbox/README.md), then [`hetzner/README.md`](hetzner/README.md).

What runs where:

| Task | Laptop devbox | Server |
|---|---|---|
| Unit tests (`devbox.sh test …`) | ✅ | optional |
| Webex join debugging against a live meeting (`devbox.sh join-debug`) | ✅ (home IP) | ✅ |
| Full stack, bots transcribing real meetings | — (too heavy for a shared laptop) | ✅ |
| Building images from your branch (`deploy.sh dev`) | — | ✅ |

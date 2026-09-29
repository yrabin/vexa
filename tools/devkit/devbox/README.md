# devbox — the repo's tooling in one container (host needs only Docker)

`Dockerfile` builds `vexa-devbox`: Node 22 + pnpm 11 (via corepack), uv (Python), git, make,
ssh, jq, redis-cli, the Docker CLI (it drives the **host's** Docker through the mounted socket),
and the Claude Code CLI. `devbox.sh` runs it with your checkout mounted at the **same path** as
on the host, plus a named volume `vexa-devbox-home` for caches, your git credentials and your
Claude login, so nothing is written to the shared laptop's home directory.

## Requirements

- Docker (Docker Desktop, OrbStack or Colima), with at least 4 GB of memory for unit tests.
- A terminal (macOS's built-in bash is fine) and VS Code for editing.

## 1. First-time setup

No git on the host? Clone with a throwaway container. The devkit lives on the branch
`claude/serene-maxwell-20w83d` until it's merged into your `main`:

```bash
mkdir -p ~/code && cd ~/code
docker run --rm -v "$PWD":"$PWD" -w "$PWD" node:22-bookworm \
  git clone -b claude/serene-maxwell-20w83d https://github.com/yrabin/vexa.git
cd vexa
tools/devkit/devbox/devbox.sh build        # ~5 min the first time
tools/devkit/devbox/devbox.sh install      # pnpm install --frozen-lockfile
```

Git identity and GitHub login live in the devbox volume, not on the laptop:

```bash
tools/devkit/devbox/devbox.sh shell
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
git config --global credential.helper store   # first push asks for username + a GitHub token
exit
```

For the token, create a **fine-grained personal access token** on GitHub, limited to `yrabin/vexa`
with *Contents: read and write*. Paste it as the password on the first push.

## 2. Daily loop

1. Edit in VS Code (`~/code/vexa`).
2. Test:
   ```bash
   tools/devkit/devbox/devbox.sh test join          # @vexa/join — the Webex work lives here
   tools/devkit/devbox/devbox.sh test bot           # @vexa/bot (builds all packages first; ~2 min cold, cached after)
   tools/devkit/devbox/devbox.sh test meeting-api   # Python, pytest
   tools/devkit/devbox/devbox.sh test agent         # Python, pytest (control plane, worker, llm)
   tools/devkit/devbox/devbox.sh test runtime       # Python, pytest
   tools/devkit/devbox/devbox.sh test node          # every Node package
   tools/devkit/devbox/devbox.sh test gates         # the static checks the pre-push hook runs
   ```
3. Commit and push from inside the devbox (the repo's pre-push hook needs Node, which only the devbox has):
   ```bash
   tools/devkit/devbox/devbox.sh shell
   git switch -c my-feature        # or stay on your branch
   git add -A && git commit -m "…"
   git push -u origin my-feature
   ```
4. Deploy on the server: `deploy.sh dev my-feature` (see [`../hetzner/README.md`](../hetzner/README.md)).

## Claude Code in the devbox

```bash
tools/devkit/devbox/devbox.sh claude
```

The first run prints a login URL: open it in your browser and paste back the code. The login is
kept in the `vexa-devbox-home` volume. Claude sees the repo exactly as the devbox does, so it can
run the same `pnpm` / `uv` test commands.

## Watching the bot join a real meeting (Webex work)

```bash
tools/devkit/devbox/devbox.sh join-debug "https://meet.google.com/xxx-xxxx-xxx"
# open http://localhost:6080/vnc.html
```

This runs `core/meetings/modules/join`'s `make debug`. The first run builds a ~2 GB
Playwright image on the host's Docker. Your `src/` edits are live: just re-run.
That target currently accepts Google Meet, Teams and Zoom URLs; the Webex work adds Webex to it.

## Other commands

| Command | Does |
|---|---|
| `devbox.sh shell` | Interactive shell in the repo |
| `devbox.sh run <cmd…>` | One command, e.g. `devbox.sh run git status` |
| `devbox.sh forget` | Delete the home volume: caches, git token, Claude login. **Do this before handing the laptop back for good.** |
| `DEVBOX_DOCKER_ARGS="-p 8000:8000" devbox.sh shell` | Extra `docker run` flags, e.g. to publish a port for a local test server |

## Troubleshooting

- **`429 Too Many Requests` while building** means Docker Hub is rate-limiting you. Build from Google's mirror of Docker Hub:
  ```bash
  tools/devkit/devbox/devbox.sh build \
    --build-arg NODE_IMAGE=mirror.gcr.io/library/node:22-bookworm \
    --build-arg DOCKER_CLI_IMAGE=mirror.gcr.io/library/docker:27-cli
  ```
- **Slow `pnpm install` or tests** is expected: macOS file sharing into Docker is slow for big `node_modules` trees.
- **Files created by the devbox are owned by root.** On macOS, Docker maps them to your user, so this only matters on a Linux host.
- **`test runtime` fails `test_docker_backend_real_container_lifecycle`** when it can't pull `alpine`. Run `docker pull alpine` once.

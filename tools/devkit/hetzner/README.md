# hetzner — run Vexa on a Hetzner Cloud server

Three files:

| File | Runs on | Does |
|---|---|---|
| `cloud-init.yaml` | Hetzner, at server creation | Creates user `dev` (SSH key only), installs Docker, Node 22, uv, adds 4 GB swap, disables password/root SSH, clones the repo |
| `deploy.sh` | Server | Syncs a branch and starts Vexa: published images, built from your branch, or Lite |
| `tunnel.sh` | Laptop | SSH-forwards the server's Vexa ports to `localhost`. Nothing but SSH is exposed publicly. |

## 1. Create an SSH key (laptop, once)

macOS ships `ssh-keygen`, so nothing needs installing. On a shared laptop, **set a passphrase**:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vexa_hetzner -C vexa-hetzner
cat ~/.ssh/vexa_hetzner.pub      # copy this line
```

## 2. Create the server (Hetzner Cloud Console)

1. Sign up at console.hetzner.cloud and create a project.
2. **Firewalls → Create firewall** `vexa-ssh-only`. Inbound: TCP port 22 only (optionally only from your IP). Delete any other inbound rule.
   *Docker-published ports bypass the server's own firewall (ufw); this Hetzner firewall sits outside the server, so it really blocks them.*
3. **Servers → Add server:**
   - **Location:** nearest to you.
   - **Image:** Ubuntu 24.04.
   - **Type:** 8 vCPU / 16 GB RAM / ≥ 160 GB disk to build from source (`deploy.sh dev`). 4 vCPU / 8 GB is enough for `deploy.sh all` or `lite` only. Shared vCPU is fine.
   - **Networking:** public IPv4 on.
   - **SSH keys:** add the `.pub` key.
   - **Firewalls:** `vexa-ssh-only`.
   - **Cloud config:** paste `cloud-init.yaml` **after** replacing the `ssh-ed25519 AAAA_REPLACE…` line with your key (and the repo URL, if different).
4. Create. Setup takes about 5 minutes after the server boots.

## 3. First login

```bash
ssh -i ~/.ssh/vexa_hetzner dev@<server-ip>
cloud-init status --wait         # "status: done"
docker version                   # Server: 26 or newer
ls ~/vexa                        # the repo
```

If `cloud-init status` says `error`, read `/var/log/cloud-init-output.log`.

The devkit lives on the branch `claude/serene-maxwell-20w83d` until merged. On the first run, call the
script from a checkout of that branch:

```bash
cd ~/vexa && git fetch origin && git checkout claude/serene-maxwell-20w83d
```

## 4. Credentials

The first `deploy.sh all|dev|bot` creates `~/vexa/deploy/compose/.env` from `.env.example`, with freshly
generated `ADMIN_TOKEN`, `INTERNAL_API_SECRET`, `VEXA_DISPATCH_SIGNING_KEY` and `NEXTAUTH_SECRET`.
Edit it (`nano ~/vexa/deploy/compose/.env`) and set:

| Need | Set | Cheap options |
|---|---|---|
| Speech-to-text (required to send bots) | `TRANSCRIPTION_SERVICE_URL` + `TRANSCRIPTION_SERVICE_TOKEN` (+ `TRANSCRIPTION_MODEL` if the provider validates it) | A free token from vexa.ai/account · Groq's free tier (`https://api.groq.com/openai`, model `whisper-large-v3-turbo`) · or Lite's bundled CPU Whisper (`deploy.sh lite`) |
| Agent chat (optional) | One of `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, or `VEXA_LLM_BASE_URL`/`VEXA_LLM_API_KEY`/`VEXA_LLM_MODEL` | Your Claude credential, or any OpenAI-compatible endpoint |

The file is `chmod 600` and git-ignored. Never commit it.

## 5. Deploy

On the server:

```bash
~/vexa/tools/devkit/hetzner/deploy.sh all                  # baseline: published images, no build
~/vexa/tools/devkit/hetzner/deploy.sh dev <your-branch>    # build bot + all services from your branch
~/vexa/tools/devkit/hetzner/deploy.sh bot <your-branch>    # rebuild just the bot image (bot-only changes)
~/vexa/tools/devkit/hetzner/deploy.sh lite                 # single container; CPU Whisper if no STT set
~/vexa/tools/devkit/hetzner/deploy.sh status | logs | down
```

- **`all`, `dev`, `bot`:** `make all` and `make dev` print your **API key** when they finish; copy it.
- **`dev`:** points `BROWSER_IMAGE` at your locally built `vexa/vexa-bot:dev`, so spawned bots run your code. The first build takes a long time (Playwright base image, every service); later builds reuse Docker's cache.
- **Pick one mode at a time.** Compose and Lite together would compete for memory. `deploy.sh down` stops both.
- **The server checkout is deploy-only.** `deploy.sh` resets the branch to `origin/<branch>` and refuses to run if tracked files were edited on the server.

## 6. Use it from the laptop

```bash
tools/devkit/hetzner/tunnel.sh <server-ip>      # keep it open; Ctrl-C closes
```

| Open | Mode |
|---|---|
| http://localhost:13000 (Terminal UI) · http://localhost:18056 (API) | Compose (`all` / `dev`) |
| http://localhost:3001 (Terminal) · http://localhost:8056 (API) | Lite |
| http://localhost:6080/vnc.html (browser view) | Lite, or `make debug` on the server |

Send a bot through the tunnel:

```bash
curl -X POST http://localhost:18056/bots -H "X-API-Key: <key>" -H "Content-Type: application/json" \
  -d '{"platform":"google_meet","native_meeting_id":"abc-defg-hij","bot_name":"Vexa"}'
```

## 7. The loop

```
laptop:  edit → devbox.sh test … → git push origin my-feature
server:  deploy.sh dev my-feature     (or: deploy.sh bot my-feature for bot-only changes)
laptop:  tunnel.sh <ip> → send a bot → watch the transcript
```

## 8. Keeping costs down

- Hetzner bills hourly while the server **exists**; a powered-off server still bills.
- To pause: take a **snapshot** (cheap), delete the server, and later recreate it from the snapshot.
- Or delete it and recreate it from `cloud-init.yaml`, which takes about 10 minutes.

## Troubleshooting

| Symptom | Check |
|---|---|
| `ssh: Permission denied` | You're using `-i ~/.ssh/vexa_hetzner`, as user `dev` (root login is disabled), and the key in cloud config matched |
| `POST /bots` → 503 | Speech-to-text isn't configured (step 4), or send `"transcribe_enabled": false` |
| Bots sit in `requested` | `docker image ls \| grep vexa-bot`: the `BROWSER_IMAGE` in `.env` must exist (`deploy.sh bot`) |
| Bot can't get into the meeting | Watch it (noVNC / `make debug`). Meeting platforms may distrust datacenter IPs; compare with a join from the laptop's `devbox.sh join-debug` |
| Disk full | `docker system df`, then `docker image prune` and `docker builder prune` |

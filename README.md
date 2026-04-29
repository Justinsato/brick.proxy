# OCP on Win PC — install kit

## What this is

OCP (https://github.com/dtzp555-max/ocp) turns your Claude **Max** subscription into an OpenAI-compatible API endpoint. We're running it in Docker on the always-on Win PC and exposing it to the internet via Cloudflare Tunnel so Vercel functions and the Mac can both consume it. Goal: **$0/month** for all Anthropic-backed flows in the BRICK family (Keystone, Intel, Box, Runner, Cockpit) — your Max plan covers it.

## Architecture

```
                  ┌──────────────────────────────────────────────────────┐
                  │  Win PC (dockerpc.local, 192.168.0.32) — always on   │
                  │                                                      │
                  │  Docker Desktop                                      │
                  │   ├── pkm-postgres        (port 5434, untouched)     │
                  │   ├── docker-mcp-gateway  (untouched)                │
                  │   └── ocp                 (port 3456) ◄── NEW        │
                  │         │                                            │
                  │         └── claude CLI (OAuth'd to Max account)      │
                  │                  │                                   │
                  │                  └── Anthropic API (Max subscription)│
                  │                                                      │
                  │  cloudflared (Windows service)                       │
                  │     │                                                │
                  └─────┼────────────────────────────────────────────────┘
                        │  encrypted tunnel
                        ▼
              ┌──────────────────────────┐
              │ Cloudflare edge          │
              │ ocp.lfiq.app (CNAME →    │
              │   <UUID>.cfargotunnel)   │
              └──────┬───────────┬───────┘
                     │           │
            ┌────────▼──┐    ┌───▼──────────────┐
            │ Vercel    │    │ Mac dev laptop   │
            │ functions │    │ (cron, scripts,  │
            │ (5 BRICK  │    │  Knowledge Edges │
            │  projects)│    │  backfill, etc.) │
            └───────────┘    └──────────────────┘
```

## Prerequisites

- **Docker Desktop** on Win PC (already installed and running per session memory).
- **Cloudflare account** (already — running `lfiq.app`, `brickston.app`, `fahq.app`, `lfigallery.com`, `lfi.app` zones).
- **Domain on Cloudflare**: we use **`lfiq.app`** since you have full DNS control there. Proposed hostname: **`ocp.lfiq.app`**.
- **`cloudflared`** on Win PC — the `setup.ps1` does NOT install this; see `cloudflared-setup.md` for the dedicated walkthrough.
- **Claude Max subscription** active and signed in (the in-container OAuth flow needs your Max account credentials).

## One-time setup (15 min)

You're at the Win PC. Open an **Administrator PowerShell** and run, in order:

### 1. Run the bootstrap script (5 min)

```powershell
# From the Win PC, in Admin PowerShell:
cd $env:USERPROFILE\Downloads
# Copy setup.ps1 from the Mac to the PC (via OneDrive, USB, or scp), then:
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

This will:
- Verify Docker Desktop is running.
- Clone `https://github.com/dtzp555-max/ocp` to `$env:USERPROFILE\ocp`.
- `docker compose up -d` to start the proxy on `localhost:3456`.
- Poll `http://localhost:3456/health` until it returns OK.
- Print the next interactive steps.

### 2. Authenticate the in-container Claude CLI to your Max account (3 min)

```powershell
docker exec -it ocp claude auth login
```

This opens a browser tab on the Win PC. Sign in with the Anthropic account that has the **Max** plan attached. If the browser doesn't auto-open, the terminal prints a URL — copy/paste it into a browser tab manually.

### 3. Issue API keys for each consumer (2 min)

See `keys.md` for the exact commands and where to paste each key. You'll generate four keys:

- `vercel-keystone`
- `vercel-intel`
- `mac-laptop`
- `knowledge-edges-cron`

### 4. Set up Cloudflare Tunnel (5 min)

Follow `cloudflared-setup.md` end to end. After this, `https://ocp.lfiq.app/health` is reachable from anywhere.

### 5. Wire env vars into Vercel + Mac

`keys.md` includes ready-to-paste `vercel env add` commands for both `brick.keystone` and `brick.intel`, plus a launchd plist snippet for the Mac.

## Verification

**From the Win PC** (immediately after step 1):

```powershell
curl http://localhost:3456/health
# Expect: {"status":"ok",...}
```

**From the Mac** (after Cloudflare tunnel is up and you've copied an API key into your shell):

```bash
export OCP_API_KEY=ocp_xxxxxxxxxxxxxxxxxxxxxxxx   # from keys.md
bash ./verify.sh
```

`verify.sh` runs three curls: health check, model list, and a real chat completion against `claude-haiku-4-5-20251001`. Expected total round-trip ~5–10s.

## Auth rotation

The OAuth token inside the container expires periodically (the Claude CLI refreshes silently while the container is up, but **container restarts can lose state** if the credentials volume isn't preserved — the compose file should mount it; verify after first run).

When auth fails (you'll see `401` from upstream Anthropic in the OCP logs), re-run:

```powershell
docker exec -it ocp claude auth login
```

Recommended cadence: re-auth proactively every **30 days**, or whenever the daily cron in Knowledge Edges starts surfacing 401s in `/intel/logs`.

## Troubleshooting

**1. Container can't reach the internet** (`curl: (6) Could not resolve host`)
- Cause: Docker Desktop's WSL2 networking stalls after Win PC sleep.
- Fix: right-click Docker Desktop tray icon → **Restart Docker Desktop**. Wait 60s, then `docker compose -f $env:USERPROFILE\ocp\docker-compose.yml up -d`.

**2. `claude auth login` browser doesn't open**
- Cause: Headless OAuth flow inside the container can't launch a browser.
- Fix: the terminal prints a URL (`https://console.anthropic.com/oauth/authorize?...`). Copy it, open it in a browser tab on the Win PC, complete the flow, and paste the resulting code back into the terminal prompt.

**3. Cloudflare Tunnel returns `502 Bad Gateway`**
- Check the service: `Get-Service cloudflared` — should be `Running`.
- Restart: `Restart-Service cloudflared`.
- Verify ingress: `Get-Content $env:USERPROFILE\.cloudflared\config.yml` — confirm `service: http://localhost:3456` (not `:3000`, not `:8080`).
- Check OCP is up locally: `curl http://localhost:3456/health` from the Win PC.
- Check tunnel status: `cloudflared tunnel info brick-ocp`.

## Cost / rate limits

Claude **Max** plan ($200/mo, 5x Pro):
- ~**1500 messages per 5-hour rolling window**.
- Resets continuously (sliding window, not hard daily cap).

Projected BRICK usage:
- Knowledge Edges backfill: ~50 calls/day (mostly Haiku 4.5).
- 5 Vercel routes (Keystone agent feed, Intel chat, Cockpit Q&A, Box clean, Runner): peak ~200 calls/day combined.
- Mac daily jobs (briefing generation, task descriptors): ~30 calls/day.

**Total: ~280 calls/day = ~60 per 5h window.** Well under the 1500 ceiling — roughly 4% utilization. Plenty of headroom for ad-hoc Claude Code sessions on top.

## Files in this kit

| File | Purpose |
|------|---------|
| `README.md` | This file. Single source of truth. |
| `setup.ps1` | One-shot Win PC bootstrap (Docker + clone + compose up). |
| `cloudflared-setup.md` | Cloudflare Tunnel install + DNS + service. |
| `keys.md` | Generate OCP keys + paste into Vercel/Mac env. |
| `verify.sh` | Mac-side end-to-end verification. |

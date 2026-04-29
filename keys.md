# OCP API keys — generate, record, distribute

You issue **one key per consumer** so you can rotate or revoke individually. Keys are printed **once** by OCP — capture them immediately into 1Password (or macOS Keychain via `security add-generic-password`).

> NEVER commit keys to git. NEVER paste them into a chat. NEVER log them.

---

## 1. Generate the four keys (Win PC, PowerShell)

Run these one at a time. Each command prints a single line like `ocp_xxxxxxxxxxxxxxxxxxxxxxxx` — copy it into 1Password before running the next.

```powershell
docker exec -it ocp ocp keys add vercel-keystone
docker exec -it ocp ocp keys add vercel-intel
docker exec -it ocp ocp keys add mac-laptop
docker exec -it ocp ocp keys add knowledge-edges-cron
```

Suggested 1Password entries (one item per key):

| Item title | Field: `OCP_API_KEY` | Field: `OCP_BASE_URL` | Notes |
|---|---|---|---|
| `OCP — vercel-keystone` | `ocp_xxx...` | `https://ocp.lfiq.app/v1` | Used by Vercel project `brick.keystone`. |
| `OCP — vercel-intel` | `ocp_xxx...` | `https://ocp.lfiq.app/v1` | Used by Vercel project `brick.intel`. |
| `OCP — mac-laptop` | `ocp_xxx...` | `https://ocp.lfiq.app/v1` | Local dev + ad-hoc Mac scripts. |
| `OCP — knowledge-edges-cron` | `ocp_xxx...` | `https://ocp.lfiq.app/v1` | Mac launchd job (`com.justinsato.knowledge-edges`). |

To list / verify keys later:

```powershell
docker exec -it ocp ocp keys list
```

To revoke:

```powershell
docker exec -it ocp ocp keys revoke <key-name>
```

---

## 2. Push keys into Vercel (run from Mac)

You need the Vercel CLI (`vercel`) signed in to the `justin-lfi` team scope. The CLI is the cleanest path here — `vercel env add` prompts interactively for the value, so secrets never appear in shell history.

### `brick.keystone`

```bash
# From the Mac:
cd /Volumes/satopkm/justinsato/Projects/ACTIVE/02-brick.keystone

# Add OCP_BASE_URL — same value across all 3 envs:
vercel env add OCP_BASE_URL production
# (paste:  https://ocp.lfiq.app/v1)
vercel env add OCP_BASE_URL preview
vercel env add OCP_BASE_URL development

# Add OCP_API_KEY — paste the vercel-keystone key for all 3 envs:
vercel env add OCP_API_KEY production
vercel env add OCP_API_KEY preview
vercel env add OCP_API_KEY development
```

### `brick.intel`

```bash
cd /Volumes/satopkm/justinsato/Projects/ACTIVE/02-brick.intel

vercel env add OCP_BASE_URL production
vercel env add OCP_BASE_URL preview
vercel env add OCP_BASE_URL development

vercel env add OCP_API_KEY production
vercel env add OCP_API_KEY preview
vercel env add OCP_API_KEY development
# (paste the vercel-intel key)
```

### Vercel REST API alternative (scriptable)

If you'd rather automate, the Vercel REST API equivalent (requires `VERCEL_TOKEN` from https://vercel.com/account/tokens and the team ID for `justin-lfi`):

```bash
# Replace placeholders:
export VERCEL_TOKEN="<your personal token>"
export TEAM_ID="<team_id for justin-lfi>"
export PROJECT_ID="<project id for brick.keystone>"   # vercel projects ls
export OCP_API_KEY="ocp_xxxxxxxxxxxxxxxxxxxxxxxx"

# OCP_BASE_URL (production, preview, development):
curl -X POST "https://api.vercel.com/v10/projects/$PROJECT_ID/env?teamId=$TEAM_ID" \
  -H "Authorization: Bearer $VERCEL_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "key": "OCP_BASE_URL",
    "value": "https://ocp.lfiq.app/v1",
    "type": "encrypted",
    "target": ["production","preview","development"]
  }'

# OCP_API_KEY:
curl -X POST "https://api.vercel.com/v10/projects/$PROJECT_ID/env?teamId=$TEAM_ID" \
  -H "Authorization: Bearer $VERCEL_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"key\": \"OCP_API_KEY\",
    \"value\": \"$OCP_API_KEY\",
    \"type\": \"encrypted\",
    \"target\": [\"production\",\"preview\",\"development\"]
  }"
```

After adding env vars, **redeploy** the project to pick them up:

```bash
vercel --prod
# or trigger a fresh deploy from the dashboard
```

---

## 3. Mac launchd plist snippet (for `knowledge-edges-cron`)

Add the env vars to your existing `com.justinsato.knowledge-edges.plist` (or create one). The relevant block:

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>OCP_BASE_URL</key>
    <string>https://ocp.lfiq.app/v1</string>
    <key>OCP_API_KEY</key>
    <string>ocp_xxxxxxxxxxxxxxxxxxxxxxxx</string>
</dict>
```

If you'd rather keep the key out of the plist (better hygiene), use the macOS Keychain and have the Python entrypoint read it:

```bash
# One-time write to Keychain:
security add-generic-password \
  -a "justinsato" \
  -s "com.justinsato.pkm.ocp_api_key" \
  -w "ocp_xxxxxxxxxxxxxxxxxxxxxxxx"

# Then in Python:
#   import subprocess
#   key = subprocess.run(
#       ["security", "find-generic-password", "-a", "justinsato",
#        "-s", "com.justinsato.pkm.ocp_api_key", "-w"],
#       capture_output=True, text=True, check=True
#   ).stdout.strip()
```

This matches the existing `com.justinsato.pkm.*` Keychain convention from your global CLAUDE.md.

---

## 4. Mac shell env (for ad-hoc dev — `mac-laptop` key)

Add to `~/.zshrc`:

```bash
export OCP_BASE_URL="https://ocp.lfiq.app/v1"
export OCP_API_KEY="$(security find-generic-password -a justinsato -s com.justinsato.pkm.ocp_api_key_mac -w 2>/dev/null)"
```

(Store the `mac-laptop` key in Keychain under service `com.justinsato.pkm.ocp_api_key_mac` to avoid hardcoding.)

---

## 5. Rotation

Every ~90 days, or whenever a key may have been exposed:

```powershell
# Win PC:
docker exec -it ocp ocp keys revoke vercel-keystone
docker exec -it ocp ocp keys add vercel-keystone
```

Then update the value in Vercel (CLI: `vercel env rm OCP_API_KEY production` → `vercel env add OCP_API_KEY production`) and redeploy. Same pattern for the Mac Keychain entry.

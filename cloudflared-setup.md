# Cloudflare Tunnel — `ocp.lfiq.app`

Goal: expose `http://localhost:3456` (OCP on the Win PC) at `https://ocp.lfiq.app` with Cloudflare's edge handling TLS, DDoS, and the public IP. No port-forwarding on the home router.

You're at the Win PC, in an **Administrator PowerShell**. Run each block in order.

---

## 1. Install `cloudflared`

```powershell
winget install --id Cloudflare.cloudflared
```

After install, open a fresh PowerShell window so the new PATH entry is picked up. Verify:

```powershell
cloudflared --version
```

---

## 2. Authenticate to Cloudflare

```powershell
cloudflared tunnel login
```

This opens a browser tab. Sign into your Cloudflare account and **pick the `lfiq.app` zone** when prompted. Cloudflare drops a cert at:

```
$env:USERPROFILE\.cloudflared\cert.pem
```

This cert authorizes `cloudflared` to manage tunnels and create DNS records in the `lfiq.app` zone on your behalf.

---

## 3. Create the tunnel

```powershell
cloudflared tunnel create brick-ocp
```

Output looks like:

```
Tunnel credentials written to C:\Users\justinsato\.cloudflared\<UUID>.json.
Created tunnel brick-ocp with id <UUID>
```

**Copy the UUID** — you'll need it in step 5.

---

## 4. Add the DNS route

This creates a CNAME at Cloudflare automatically (`ocp.lfiq.app` → `<UUID>.cfargotunnel.com`):

```powershell
cloudflared tunnel route dns brick-ocp ocp.lfiq.app
```

Verify the record exists with a public DNS check:

```powershell
nslookup ocp.lfiq.app 1.1.1.1
```

Expect a CNAME pointing at `*.cfargotunnel.com`.

> Note: `lfiq.app` already has a wildcard `*.lfiq.app` CNAME at Cloudflare (per existing setup memory). The explicit `ocp` record takes precedence over the wildcard — no conflict, but worth knowing.

---

## 5. Write the tunnel config

Create `$env:USERPROFILE\.cloudflared\config.yml`. Replace `<UUID>` with the value from step 3.

```yaml
tunnel: <UUID>
credentials-file: C:\Users\justinsato\.cloudflared\<UUID>.json

ingress:
  - hostname: ocp.lfiq.app
    service: http://localhost:3456
    originRequest:
      connectTimeout: 30s
      noTLSVerify: false
  - service: http_status:404
```

You can write it directly from PowerShell if you'd like (substitute `<UUID>`):

```powershell
@"
tunnel: <UUID>
credentials-file: C:\Users\justinsato\.cloudflared\<UUID>.json

ingress:
  - hostname: ocp.lfiq.app
    service: http://localhost:3456
    originRequest:
      connectTimeout: 30s
      noTLSVerify: false
  - service: http_status:404
"@ | Set-Content -Path "$env:USERPROFILE\.cloudflared\config.yml" -Encoding UTF8
```

Validate:

```powershell
cloudflared tunnel ingress validate
```

Expect: `Validating rules from C:\Users\justinsato\.cloudflared\config.yml — OK`.

---

## 6. Install + start as a Windows service

```powershell
cloudflared service install
Start-Service cloudflared
Get-Service cloudflared
```

Expect `Status: Running`. The service starts automatically on Win PC boot from now on.

---

## 7. Verify end-to-end

From **any device** (Mac, phone on LTE, anywhere):

```bash
curl -sS https://ocp.lfiq.app/health
```

Expect a JSON response with `"status":"ok"` (or whatever OCP's health route returns). Round-trip should be sub-second.

---

## Operational notes

- **Restart after config edits**: `Restart-Service cloudflared`.
- **Live logs**: `Get-EventLog -LogName Application -Source cloudflared -Newest 50` — or run `cloudflared tunnel run brick-ocp` in a foreground terminal for live stdout while debugging.
- **Tunnel is encrypted edge-to-origin**: Cloudflare terminates TLS at the edge with a Cloudflare-managed cert for `*.lfiq.app`; `cloudflared` opens an outbound-only QUIC connection from your Win PC to the Cloudflare edge. No inbound port needs opening on the home router.
- **Renaming/deleting**: `cloudflared tunnel delete brick-ocp` (must stop service first), then re-create.

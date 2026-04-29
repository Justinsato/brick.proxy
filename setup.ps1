# setup.ps1 — OCP bootstrap for Win PC
#
# Run from an Administrator PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# Idempotent: re-running is safe. It will:
#   1. Verify Docker Desktop is running.
#   2. Clone (or pull) https://github.com/dtzp555-max/ocp into $env:USERPROFILE\ocp.
#   3. docker compose up -d.
#   4. Poll http://localhost:3456/health until OK or 60s timeout.
#   5. Print interactive next-step commands.

$ErrorActionPreference = "Stop"
$OcpDir = Join-Path $env:USERPROFILE "ocp"
$RepoUrl = "https://github.com/dtzp555-max/ocp.git"
$HealthUrl = "http://localhost:3456/health"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Write-OK($msg) {
    Write-Host "    [OK] $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Write-Host "    [WARN] $msg" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 1. Verify Docker Desktop
# ---------------------------------------------------------------------------
Write-Step "Verifying Docker Desktop is running"
try {
    $dockerInfo = docker info --format '{{.ServerVersion}}' 2>$null
    if (-not $dockerInfo) {
        throw "docker info returned nothing"
    }
    Write-OK "Docker server version $dockerInfo"
} catch {
    Write-Host "    [FAIL] Docker is not reachable. Start Docker Desktop and re-run this script." -ForegroundColor Red
    exit 1
}

# Verify git is on PATH
try {
    $gitVersion = git --version 2>$null
    Write-OK "git: $gitVersion"
} catch {
    Write-Host "    [FAIL] git is not on PATH. Install Git for Windows: winget install --id Git.Git" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# 2. Clone or pull OCP
# ---------------------------------------------------------------------------
Write-Step "Setting up $OcpDir"
if (Test-Path $OcpDir) {
    Write-OK "Directory exists — pulling latest"
    Push-Location $OcpDir
    try {
        git pull --ff-only
    } catch {
        Write-Warn "git pull failed (working tree may have local changes); continuing with current checkout"
    } finally {
        Pop-Location
    }
} else {
    Write-Host "    Cloning $RepoUrl"
    git clone $RepoUrl $OcpDir
    Write-OK "Cloned"
}

# Sanity: compose file present?
$ComposeFile = Join-Path $OcpDir "docker-compose.yml"
if (-not (Test-Path $ComposeFile)) {
    $ComposeFile = Join-Path $OcpDir "compose.yml"
}
if (-not (Test-Path $ComposeFile)) {
    Write-Host "    [FAIL] No docker-compose.yml or compose.yml found in $OcpDir" -ForegroundColor Red
    Write-Host "           Inspect the repo layout — the OCP project may have moved files." -ForegroundColor Red
    exit 1
}
Write-OK "Compose file: $ComposeFile"

# ---------------------------------------------------------------------------
# 3. docker compose up -d
# ---------------------------------------------------------------------------
Write-Step "Starting OCP container (docker compose up -d)"
Push-Location $OcpDir
try {
    docker compose up -d
} finally {
    Pop-Location
}
Write-OK "Compose started"

# ---------------------------------------------------------------------------
# 4. Health poll
# ---------------------------------------------------------------------------
Write-Step "Waiting for OCP to report healthy at $HealthUrl"
$deadline = (Get-Date).AddSeconds(60)
$healthy = $false
while ((Get-Date) -lt $deadline) {
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $HealthUrl -TimeoutSec 3
        if ($resp.StatusCode -eq 200) {
            $healthy = $true
            Write-OK "Health: $($resp.Content)"
            break
        }
    } catch {
        # not ready yet
    }
    Start-Sleep -Seconds 2
}

if (-not $healthy) {
    Write-Warn "Container did not respond healthy within 60s. Check logs:"
    Write-Host "    docker logs ocp --tail 100" -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------------------
# 5. Next steps
# ---------------------------------------------------------------------------
Write-Step "Next steps (run these manually)"

Write-Host @"

  [A] Authenticate Claude CLI inside the container (one-time, opens browser):

      docker exec -it ocp claude auth login

      Sign in with the Anthropic account that has the Max plan.
      If the browser does not auto-open, copy the printed URL into a tab.

  [B] Generate API keys for each consumer (see keys.md for full list):

      docker exec -it ocp ocp keys add vercel-keystone
      docker exec -it ocp ocp keys add vercel-intel
      docker exec -it ocp ocp keys add mac-laptop
      docker exec -it ocp ocp keys add knowledge-edges-cron

      Each command prints a single key (ocp_xxxx...). Save them in 1Password.

  [C] Set up Cloudflare Tunnel — see cloudflared-setup.md.

  [D] Verify from the Mac after the tunnel is live — see verify.sh.

"@ -ForegroundColor White

Write-Host "==> Bootstrap complete. OCP is running locally on port 3456." -ForegroundColor Green

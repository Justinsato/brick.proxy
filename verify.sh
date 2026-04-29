#!/usr/bin/env bash
# verify.sh — confirm OCP is reachable from the Mac via Cloudflare Tunnel.
#
# Usage:
#   export OCP_API_KEY=ocp_xxxxxxxxxxxxxxxxxxxxxxxx   # the mac-laptop key
#   bash ./verify.sh
#
# Or with a different base URL / model:
#   OCP_BASE_URL=https://ocp.lfiq.app MODEL=claude-sonnet-4-5-20250929 bash ./verify.sh

set -euo pipefail

BASE_URL="${OCP_BASE_URL:-https://ocp.lfiq.app}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"

if [[ -z "${OCP_API_KEY:-}" ]]; then
  echo "FAIL: OCP_API_KEY is not set." >&2
  echo "      Run: export OCP_API_KEY=ocp_xxx... (the mac-laptop key from 1Password)" >&2
  exit 1
fi

# Strip trailing /v1 if present so we can build both /health and /v1/* cleanly.
HOST_URL="${BASE_URL%/v1}"

echo "==> 1. Health check"
echo "    GET ${HOST_URL}/health"
HEALTH=$(curl -sS --fail-with-body "${HOST_URL}/health" || {
  echo "FAIL: /health did not return 200" >&2
  exit 1
})
echo "    $HEALTH"
echo

echo "==> 2. Model list (auth check)"
echo "    GET ${HOST_URL}/v1/models"
MODELS=$(curl -sS --fail-with-body \
  "${HOST_URL}/v1/models" \
  -H "Authorization: Bearer ${OCP_API_KEY}" || {
  echo "FAIL: /v1/models did not return 200. Auth header may be wrong." >&2
  exit 1
})
echo "    $(echo "$MODELS" | head -c 400)..."
echo

echo "==> 3. Live chat completion (round-trip to Anthropic via Max)"
echo "    POST ${HOST_URL}/v1/chat/completions  (model: $MODEL)"
START=$(date +%s)
RESP=$(curl -sS --fail-with-body \
  -X POST "${HOST_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${OCP_API_KEY}" \
  -d "{
    \"model\": \"${MODEL}\",
    \"messages\": [
      {\"role\": \"user\", \"content\": \"say hello and the current Anthropic model name\"}
    ]
  }" || {
  echo "FAIL: chat completion errored" >&2
  exit 1
})
END=$(date +%s)
ELAPSED=$((END - START))

echo "    elapsed: ${ELAPSED}s"
echo
echo "    Response:"
echo "$RESP" | sed 's/^/      /'
echo

echo "==> ALL CHECKS PASSED"
echo "    OCP at $HOST_URL is reachable, authenticated, and serving completions."

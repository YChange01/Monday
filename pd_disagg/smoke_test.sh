#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python3}"
ROUTER_ADDR="${ROUTER_ADDR:-127.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-18080}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3-8b}"
SMOKE_MODE="${SMOKE_MODE:-native}"
SMOKE_TEXT="${SMOKE_TEXT:-ping}"
SMOKE_MAX_NEW_TOKENS="${SMOKE_MAX_NEW_TOKENS:-8}"
BASE_URL="${BASE_URL:-http://${ROUTER_ADDR}:${ROUTER_PORT}}"

LOCAL_NO_PROXY="localhost,127.0.0.1,::1,0.0.0.0,${ROUTER_ADDR}"
export NO_PROXY="${NO_PROXY:+${NO_PROXY},}${LOCAL_NO_PROXY}"
export no_proxy="${no_proxy:+${no_proxy},}${LOCAL_NO_PROXY}"

send_json() {
  local url="$1"
  local body="$2"
  local response_file status
  response_file="$(mktemp)"

  status="$(curl -sS -o "$response_file" -w "%{http_code}" "$url" \
    -H "Content-Type: application/json" \
    -d "$body" || true)"

  if [[ "$status" != 2* ]]; then
    echo "Request failed: HTTP ${status}"
    cat "$response_file"
    rm -f "$response_file"
    exit 1
  fi

  "$PYTHON_BIN" -m json.tool < "$response_file"
  rm -f "$response_file"
}

echo "Health check: ${BASE_URL}/health"
curl -fsS "${BASE_URL}/health" >/dev/null

if [[ "$SMOKE_MODE" == "chat" ]]; then
  echo "Sending OpenAI-compatible chat smoke request..."
  send_json "${BASE_URL}/v1/chat/completions" "$(cat <<JSON
{
  "model": "${SERVED_MODEL_NAME}",
  "messages": [
    {"role": "user", "content": "${SMOKE_TEXT}"}
  ],
  "temperature": 0,
  "max_tokens": ${SMOKE_MAX_NEW_TOKENS},
  "stream": false
}
JSON
)"
else
  echo "Sending native /generate smoke request..."
  send_json "${BASE_URL}/generate" "$(cat <<JSON
{
  "text": "${SMOKE_TEXT}",
  "sampling_params": {
    "temperature": 0,
    "max_new_tokens": ${SMOKE_MAX_NEW_TOKENS}
  }
}
JSON
)"
fi

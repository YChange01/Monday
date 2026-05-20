#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python3}"
ROUTER_ADDR="${ROUTER_ADDR:-127.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3-8b}"
SMOKE_MODE="${SMOKE_MODE:-native}"
BASE_URL="${BASE_URL:-http://${ROUTER_ADDR}:${ROUTER_PORT}}"

echo "Health check: ${BASE_URL}/health"
curl -fsS "${BASE_URL}/health" >/dev/null

if [[ "$SMOKE_MODE" == "chat" ]]; then
  echo "Sending OpenAI-compatible chat smoke request..."
  curl -fsS "${BASE_URL}/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d @- <<JSON | "$PYTHON_BIN" -m json.tool
{
  "model": "${SERVED_MODEL_NAME}",
  "messages": [
    {"role": "user", "content": "Give one sentence explaining prefill/decode disaggregation."}
  ],
  "temperature": 0,
  "max_tokens": 64,
  "stream": false
}
JSON
else
  echo "Sending native /generate smoke request..."
  curl -fsS "${BASE_URL}/generate" \
    -H "Content-Type: application/json" \
    -d @- <<JSON | "$PYTHON_BIN" -m json.tool
{
  "text": "Give one sentence explaining prefill/decode disaggregation.",
  "sampling_params": {
    "temperature": 0,
    "max_new_tokens": 64
  }
}
JSON
fi

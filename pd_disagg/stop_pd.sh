#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PID_FILE="${PID_FILE:-${SCRIPT_DIR}/run/pd_qwen3_32b.pid}"

if [[ ! -f "$PID_FILE" ]]; then
  echo "PID file not found: ${PID_FILE}"
  exit 0
fi

echo "Stopping processes from ${PID_FILE}"
while read -r pid role endpoint log_file; do
  [[ -z "${pid:-}" ]] && continue
  if kill -0 "$pid" >/dev/null 2>&1; then
    echo "Stopping ${role} ${endpoint} pid=${pid}"
    kill "$pid" >/dev/null 2>&1 || true
  fi
done < "$PID_FILE"

sleep 3

while read -r pid role endpoint log_file; do
  [[ -z "${pid:-}" ]] && continue
  if kill -0 "$pid" >/dev/null 2>&1; then
    echo "Force stopping ${role} ${endpoint} pid=${pid}"
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi
done < "$PID_FILE"

rm -f "$PID_FILE"
echo "Stopped."

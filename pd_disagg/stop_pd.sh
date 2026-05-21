#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DEFAULT_PID_FILE="${SCRIPT_DIR}/run/pd_qwen3_32b.pid"
LEGACY_PID_FILE="${SCRIPT_DIR}/run/pd_qwen3_8b.pid"

stop_pid_file() {
  local pid_file="$1"

  if [[ ! -f "$pid_file" ]]; then
    echo "PID file not found: ${pid_file}"
    return 0
  fi

  echo "Stopping processes from ${pid_file}"
  while read -r pid role endpoint log_file; do
    [[ -z "${pid:-}" ]] && continue
    if kill -0 "$pid" >/dev/null 2>&1; then
      echo "Stopping ${role} ${endpoint} pid=${pid}"
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done < "$pid_file"

  sleep 3

  while read -r pid role endpoint log_file; do
    [[ -z "${pid:-}" ]] && continue
    if kill -0 "$pid" >/dev/null 2>&1; then
      echo "Force stopping ${role} ${endpoint} pid=${pid}"
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  done < "$pid_file"

  rm -f "$pid_file"
}

if [[ -n "${PID_FILE:-}" ]]; then
  stop_pid_file "$PID_FILE"
else
  stop_pid_file "$DEFAULT_PID_FILE"
  stop_pid_file "$LEGACY_PID_FILE"
fi

echo "Stopped."

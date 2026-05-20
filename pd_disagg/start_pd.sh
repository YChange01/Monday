#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-${SCRIPT_DIR}/env.b200.local.sh}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"
MODEL_PATH="${MODEL_PATH:-Qwen/Qwen3-32B}"
TOKENIZER_PATH="${TOKENIZER_PATH:-$MODEL_PATH}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3-32b}"
REASONING_PARSER="${REASONING_PARSER:-qwen3}"

PREFILL_GROUPS="${PREFILL_GROUPS:-0}"
DECODE_GROUPS="${DECODE_GROUPS:-1}"

WORKER_HOST="${WORKER_HOST:-0.0.0.0}"
WORKER_ADDR="${WORKER_ADDR:-127.0.0.1}"
ROUTER_HOST="${ROUTER_HOST:-0.0.0.0}"
ROUTER_ADDR="${ROUTER_ADDR:-127.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
PREFILL_PORT_START="${PREFILL_PORT_START:-30000}"
DECODE_PORT_START="${DECODE_PORT_START:-30010}"
BOOTSTRAP_PORT_START="${BOOTSTRAP_PORT_START:-8998}"

TRANSFER_BACKEND="${TRANSFER_BACKEND:-mooncake}"
DTYPE="${DTYPE:-bfloat16}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-32768}"
PREFILL_MEM_FRACTION_STATIC="${PREFILL_MEM_FRACTION_STATIC:-0.78}"
DECODE_MEM_FRACTION_STATIC="${DECODE_MEM_FRACTION_STATIC:-0.86}"

PREFILL_POLICY="${PREFILL_POLICY:-cache_aware}"
DECODE_POLICY="${DECODE_POLICY:-power_of_two}"
ROUTER_WORKER_STARTUP_TIMEOUT_SECS="${ROUTER_WORKER_STARTUP_TIMEOUT_SECS:-1800}"
READY_TIMEOUT_SECS="${READY_TIMEOUT_SECS:-1800}"

LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
PID_FILE="${PID_FILE:-${SCRIPT_DIR}/run/pd_qwen3_32b.pid}"

mkdir -p "$LOG_DIR" "$(dirname "$PID_FILE")"
: > "$PID_FILE"

export SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT="${SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT:-600}"
export SGLANG_DISAGGREGATION_WAITING_TIMEOUT="${SGLANG_DISAGGREGATION_WAITING_TIMEOUT:-600}"

count_gpus() {
  local group="${1// /}"
  if [[ -z "$group" ]]; then
    echo "0"
  else
    awk -F, '{print NF}' <<< "$group"
  fi
}

build_server_args() {
  local mem_fraction="$1"
  SERVER_ARGS=(
    --model-path "$MODEL_PATH"
    --served-model-name "$SERVED_MODEL_NAME"
    --host "$WORKER_HOST"
    --dtype "$DTYPE"
    --context-length "$CONTEXT_LENGTH"
    --mem-fraction-static "$mem_fraction"
    --trust-remote-code
    --reasoning-parser "$REASONING_PARSER"
    --disaggregation-transfer-backend "$TRANSFER_BACKEND"
  )
}

wait_for_health() {
  local url="$1"
  local deadline=$((SECONDS + READY_TIMEOUT_SECS))

  echo "Waiting for router: ${url}/health"
  until curl -fsS "${url}/health" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for router. Check logs in ${LOG_DIR}."
      return 1
    fi
    sleep 10
  done
  echo "Router is healthy."
}

launch_prefill_workers() {
  IFS=';' read -r -a groups <<< "$PREFILL_GROUPS"
  for idx in "${!groups[@]}"; do
    local group="${groups[$idx]// /}"
    [[ -z "$group" ]] && continue

    local port=$((PREFILL_PORT_START + idx))
    local bootstrap_port=$((BOOTSTRAP_PORT_START + idx))
    local tp_size
    tp_size="$(count_gpus "$group")"

    build_server_args "$PREFILL_MEM_FRACTION_STATIC"
    local args=(
      "${SERVER_ARGS[@]}"
      --disaggregation-mode prefill
      --port "$port"
      --tp-size "$tp_size"
      --disaggregation-bootstrap-port "$bootstrap_port"
    )

    local log_file="${LOG_DIR}/prefill_${idx}.log"
    echo "Starting prefill worker ${idx}: GPUs=${group}, port=${port}, bootstrap=${bootstrap_port}, tp=${tp_size}"
    CUDA_VISIBLE_DEVICES="$group" nohup "$PYTHON_BIN" -m sglang.launch_server "${args[@]}" > "$log_file" 2>&1 &
    local pid=$!
    echo "$pid prefill ${WORKER_ADDR}:${port} ${log_file}" >> "$PID_FILE"
    PREFILL_URL_ARGS+=(--prefill "http://${WORKER_ADDR}:${port}" "$bootstrap_port")
  done
}

launch_decode_workers() {
  IFS=';' read -r -a groups <<< "$DECODE_GROUPS"
  for idx in "${!groups[@]}"; do
    local group="${groups[$idx]// /}"
    [[ -z "$group" ]] && continue

    local port=$((DECODE_PORT_START + idx))
    local tp_size
    tp_size="$(count_gpus "$group")"

    build_server_args "$DECODE_MEM_FRACTION_STATIC"
    local args=(
      "${SERVER_ARGS[@]}"
      --disaggregation-mode decode
      --port "$port"
      --tp-size "$tp_size"
      --base-gpu-id 0
    )

    local log_file="${LOG_DIR}/decode_${idx}.log"
    echo "Starting decode worker ${idx}: GPUs=${group}, port=${port}, tp=${tp_size}"
    CUDA_VISIBLE_DEVICES="$group" nohup "$PYTHON_BIN" -m sglang.launch_server "${args[@]}" > "$log_file" 2>&1 &
    local pid=$!
    echo "$pid decode ${WORKER_ADDR}:${port} ${log_file}" >> "$PID_FILE"
    DECODE_URL_ARGS+=(--decode "http://${WORKER_ADDR}:${port}")
  done
}

launch_router() {
  local args=(
    --pd-disaggregation
    --host "$ROUTER_HOST"
    --port "$ROUTER_PORT"
    --worker-startup-timeout-secs "$ROUTER_WORKER_STARTUP_TIMEOUT_SECS"
    --model-path "$MODEL_PATH"
    --tokenizer-path "$TOKENIZER_PATH"
    --prefill-policy "$PREFILL_POLICY"
    --decode-policy "$DECODE_POLICY"
    --reasoning-parser "$REASONING_PARSER"
  )

  local log_file="${LOG_DIR}/router.log"
  echo "Starting router: ${ROUTER_HOST}:${ROUTER_PORT}"
  nohup "$PYTHON_BIN" -m sglang_router.launch_router "${args[@]}" "${PREFILL_URL_ARGS[@]}" "${DECODE_URL_ARGS[@]}" > "$log_file" 2>&1 &
  local pid=$!
  echo "$pid router ${ROUTER_ADDR}:${ROUTER_PORT} ${log_file}" >> "$PID_FILE"
}

PREFILL_URL_ARGS=()
DECODE_URL_ARGS=()

launch_prefill_workers
launch_decode_workers

if [[ "${#PREFILL_URL_ARGS[@]}" -eq 0 || "${#DECODE_URL_ARGS[@]}" -eq 0 ]]; then
  echo "No prefill or decode workers were configured. Check PREFILL_GROUPS and DECODE_GROUPS."
  exit 1
fi

launch_router

echo "PID file: ${PID_FILE}"
echo "Logs: ${LOG_DIR}"
echo "Router base URL: http://${ROUTER_ADDR}:${ROUTER_PORT}"

wait_for_health "http://${ROUTER_ADDR}:${ROUTER_PORT}"

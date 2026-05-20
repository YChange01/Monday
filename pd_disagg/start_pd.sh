#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python3}"
MODEL_PATH="${MODEL_PATH:-/mnt/nvme3n1/g00872988/models/Qwen3-8B}"
TOKENIZER_PATH="${TOKENIZER_PATH:-$MODEL_PATH}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3-8b}"
REASONING_PARSER="${REASONING_PARSER:-qwen3}"

PREFILL_GROUPS="${PREFILL_GROUPS:-4}"
DECODE_GROUPS="${DECODE_GROUPS:-5}"

WORKER_HOST="${WORKER_HOST:-0.0.0.0}"
WORKER_ADDR="${WORKER_ADDR:-127.0.0.1}"
ROUTER_HOST="${ROUTER_HOST:-0.0.0.0}"
ROUTER_ADDR="${ROUTER_ADDR:-127.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-18080}"
PREFILL_PORT_START="${PREFILL_PORT_START:-18100}"
DECODE_PORT_START="${DECODE_PORT_START:-18200}"
BOOTSTRAP_PORT_START="${BOOTSTRAP_PORT_START:-18300}"

TRANSFER_BACKEND="${TRANSFER_BACKEND:-nixl}"
DTYPE="${DTYPE:-bfloat16}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-32768}"
PREFILL_MEM_FRACTION_STATIC="${PREFILL_MEM_FRACTION_STATIC:-0.78}"
DECODE_MEM_FRACTION_STATIC="${DECODE_MEM_FRACTION_STATIC:-0.86}"

PREFILL_POLICY="${PREFILL_POLICY:-cache_aware}"
DECODE_POLICY="${DECODE_POLICY:-round_robin}"
ROUTER_WORKER_STARTUP_TIMEOUT_SECS="${ROUTER_WORKER_STARTUP_TIMEOUT_SECS:-1800}"
READY_TIMEOUT_SECS="${READY_TIMEOUT_SECS:-1800}"

LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
PID_FILE="${PID_FILE:-${SCRIPT_DIR}/run/pd_qwen3_8b.pid}"

mkdir -p "$LOG_DIR" "$(dirname "$PID_FILE")"

if [[ -s "$PID_FILE" ]]; then
  while read -r pid role endpoint log_file; do
    [[ -z "${pid:-}" ]] && continue
    if kill -0 "$pid" >/dev/null 2>&1; then
      echo "Existing ${role} process is still running: pid=${pid}, endpoint=${endpoint}"
      echo "Run ./stop_pd.sh before starting again."
      exit 1
    fi
  done < "$PID_FILE"
fi

: > "$PID_FILE"

export SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT="${SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT:-600}"
export SGLANG_DISAGGREGATION_WAITING_TIMEOUT="${SGLANG_DISAGGREGATION_WAITING_TIMEOUT:-600}"

configure_transfer_backend() {
  case "$TRANSFER_BACKEND" in
    nixl)
      export SGLANG_DISAGGREGATION_NIXL_BACKEND="${SGLANG_DISAGGREGATION_NIXL_BACKEND:-UCX}"
      if ! "$PYTHON_BIN" -c 'from nixl._api import nixl_agent' >/dev/null 2>&1; then
        echo "TRANSFER_BACKEND=nixl requires the nixl Python package in ${PYTHON_BIN}."
        echo "Install it in the active environment, or run with TRANSFER_BACKEND=mooncake after fixing Mooncake/RDMA."
        exit 1
      fi
      ;;
    mooncake)
      export SGLANG_MOONCAKE_CUSTOM_MEM_POOL="${SGLANG_MOONCAKE_CUSTOM_MEM_POOL:-INTRA_NODE_NVLINK}"
      export MC_INTRANODE_NVLINK="${MC_INTRANODE_NVLINK:-true}"
      ;;
    ascend|fake|mori)
      ;;
    *)
      echo "Unsupported TRANSFER_BACKEND=${TRANSFER_BACKEND}. Use nixl, mooncake, ascend, fake, or mori."
      exit 1
      ;;
  esac
}

configure_transfer_backend

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

wait_for_generate() {
  local url="$1"
  local deadline=$((SECONDS + READY_TIMEOUT_SECS))

  echo "Waiting for PD generation readiness: ${url}/generate"
  until curl -fsS "${url}/generate" \
    -H "Content-Type: application/json" \
    -d '{"text":"ping","sampling_params":{"temperature":0,"max_new_tokens":1}}' \
    >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for PD generation readiness. Check logs in ${LOG_DIR}."
      return 1
    fi
    sleep 10
  done
  echo "PD generation is ready."
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
echo "Transfer backend: ${TRANSFER_BACKEND}"

wait_for_health "http://${ROUTER_ADDR}:${ROUTER_PORT}"
wait_for_generate "http://${ROUTER_ADDR}:${ROUTER_PORT}"

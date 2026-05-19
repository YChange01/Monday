#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${1:-${SCRIPT_DIR}/env.b200.local.sh}"

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
elif [[ -f "${SCRIPT_DIR}/env.b200.example.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/env.b200.example.sh"
fi

if [[ -z "${SGLANG_DIR:-}" ]]; then
  SGLANG_DIR="$(cd "${SCRIPT_DIR}/../sglang" && pwd)"
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"
MODEL_PATH="${MODEL_PATH:-Qwen/Qwen3-32B}"
TOKENIZER_PATH="${TOKENIZER_PATH:-$MODEL_PATH}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3-32b}"
REASONING_PARSER="${REASONING_PARSER:-qwen3}"
TRUST_REMOTE_CODE="${TRUST_REMOTE_CODE:-1}"

PREFILL_GROUPS="${PREFILL_GROUPS:-0}"
DECODE_GROUPS="${DECODE_GROUPS:-1}"
PREFILL_TP_SIZE="${PREFILL_TP_SIZE:-auto}"
DECODE_TP_SIZE="${DECODE_TP_SIZE:-auto}"

WORKER_HOST="${WORKER_HOST:-0.0.0.0}"
WORKER_ADDR="${WORKER_ADDR:-127.0.0.1}"
ROUTER_HOST="${ROUTER_HOST:-0.0.0.0}"
ROUTER_ADDR="${ROUTER_ADDR:-127.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-8000}"
PREFILL_PORT_START="${PREFILL_PORT_START:-30000}"
DECODE_PORT_START="${DECODE_PORT_START:-30010}"
BOOTSTRAP_PORT_START="${BOOTSTRAP_PORT_START:-8998}"

TRANSFER_BACKEND="${TRANSFER_BACKEND:-mooncake}"
DISAGG_IB_DEVICE="${DISAGG_IB_DEVICE:-}"
MOONCAKE_MEM_POOL="${MOONCAKE_MEM_POOL:-}"
ENABLE_STAGING_BUFFER="${ENABLE_STAGING_BUFFER:-0}"
STAGING_BUFFER_SIZE_MB="${STAGING_BUFFER_SIZE_MB:-64}"
STAGING_POOL_SIZE_MB="${STAGING_POOL_SIZE_MB:-4096}"

DTYPE="${DTYPE:-bfloat16}"
CONTEXT_LENGTH="${CONTEXT_LENGTH:-32768}"
PREFILL_MEM_FRACTION_STATIC="${PREFILL_MEM_FRACTION_STATIC:-0.78}"
DECODE_MEM_FRACTION_STATIC="${DECODE_MEM_FRACTION_STATIC:-0.86}"
CHUNKED_PREFILL_SIZE="${CHUNKED_PREFILL_SIZE:-}"
PREFILL_MAX_RUNNING_REQUESTS="${PREFILL_MAX_RUNNING_REQUESTS:-}"
DECODE_MAX_RUNNING_REQUESTS="${DECODE_MAX_RUNNING_REQUESTS:-128}"
CUDA_GRAPH_MAX_BS="${CUDA_GRAPH_MAX_BS:-}"
ATTENTION_BACKEND="${ATTENTION_BACKEND:-}"
KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-}"
QUANTIZATION="${QUANTIZATION:-}"
DISABLE_RADIX_CACHE="${DISABLE_RADIX_CACHE:-0}"
DISABLE_CUDA_GRAPH="${DISABLE_CUDA_GRAPH:-0}"
SKIP_SERVER_WARMUP="${SKIP_SERVER_WARMUP:-0}"
ENABLE_DP_ATTENTION="${ENABLE_DP_ATTENTION:-0}"
PREFILL_DP_SIZE="${PREFILL_DP_SIZE:-}"
DECODE_DP_SIZE="${DECODE_DP_SIZE:-}"

ROUTER_WORKER_STARTUP_TIMEOUT_SECS="${ROUTER_WORKER_STARTUP_TIMEOUT_SECS:-1800}"
ROUTER_WORKER_STARTUP_CHECK_INTERVAL="${ROUTER_WORKER_STARTUP_CHECK_INTERVAL:-30}"
ROUTER_POLICY="${ROUTER_POLICY:-cache_aware}"
PREFILL_POLICY="${PREFILL_POLICY:-cache_aware}"
DECODE_POLICY="${DECODE_POLICY:-power_of_two}"
ROUTER_LOG_LEVEL="${ROUTER_LOG_LEVEL:-info}"

EXTRA_SERVER_ARGS="${EXTRA_SERVER_ARGS:-}"
PREFILL_EXTRA_ARGS="${PREFILL_EXTRA_ARGS:-}"
DECODE_EXTRA_ARGS="${DECODE_EXTRA_ARGS:-}"
ROUTER_EXTRA_ARGS="${ROUTER_EXTRA_ARGS:-}"

LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
PID_FILE="${PID_FILE:-${SCRIPT_DIR}/run/pd_qwen3_32b.pid}"
WAIT_FOR_READY="${WAIT_FOR_READY:-1}"
READY_TIMEOUT_SECS="${READY_TIMEOUT_SECS:-1800}"

mkdir -p "$LOG_DIR" "$(dirname "$PID_FILE")"
: > "$PID_FILE"

export PYTHONPATH="${SGLANG_DIR}/python:${SGLANG_DIR}/sgl-model-gateway/bindings/python/src:${PYTHONPATH:-}"
export SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT="${SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT:-600}"
export SGLANG_DISAGGREGATION_WAITING_TIMEOUT="${SGLANG_DISAGGREGATION_WAITING_TIMEOUT:-600}"

if [[ -n "$MOONCAKE_MEM_POOL" ]]; then
  export SGLANG_MOONCAKE_CUSTOM_MEM_POOL="$MOONCAKE_MEM_POOL"
  if [[ "$MOONCAKE_MEM_POOL" == "NVLINK" ]]; then
    export MC_FORCE_MNNVL="${MC_FORCE_MNNVL:-True}"
  elif [[ "$MOONCAKE_MEM_POOL" == "INTRA_NODE_NVLINK" ]]; then
    export MC_INTRANODE_NVLINK="${MC_INTRANODE_NVLINK:-true}"
  fi
fi

if [[ "$ENABLE_STAGING_BUFFER" == "1" ]]; then
  export SGLANG_DISAGG_STAGING_BUFFER=1
  export SGLANG_DISAGG_STAGING_BUFFER_SIZE_MB="$STAGING_BUFFER_SIZE_MB"
  export SGLANG_DISAGG_STAGING_POOL_SIZE_MB="$STAGING_POOL_SIZE_MB"
fi

count_gpus() {
  local group="${1// /}"
  if [[ -z "$group" ]]; then
    echo "0"
  else
    awk -F, '{print NF}' <<< "$group"
  fi
}

append_extra_args() {
  local extra="$1"
  if [[ -n "$extra" ]]; then
    # Intentional word splitting for simple extra CLI flags.
    # shellcheck disable=SC2206
    EXTRA_WORDS=( $extra )
    printf '%s\0' "${EXTRA_WORDS[@]}"
  fi
}

add_common_server_args() {
  local mem_fraction="$1"
  COMMON_ARGS=(
    --model-path "$MODEL_PATH"
    --host "$WORKER_HOST"
    --dtype "$DTYPE"
    --mem-fraction-static "$mem_fraction"
  )

  if [[ -n "$SERVED_MODEL_NAME" ]]; then
    COMMON_ARGS+=(--served-model-name "$SERVED_MODEL_NAME")
  fi
  if [[ "$TRUST_REMOTE_CODE" == "1" ]]; then
    COMMON_ARGS+=(--trust-remote-code)
  fi
  if [[ -n "$REASONING_PARSER" ]]; then
    COMMON_ARGS+=(--reasoning-parser "$REASONING_PARSER")
  fi
  if [[ -n "$CONTEXT_LENGTH" ]]; then
    COMMON_ARGS+=(--context-length "$CONTEXT_LENGTH")
  fi
  if [[ -n "$CHUNKED_PREFILL_SIZE" ]]; then
    COMMON_ARGS+=(--chunked-prefill-size "$CHUNKED_PREFILL_SIZE")
  fi
  if [[ -n "$ATTENTION_BACKEND" ]]; then
    COMMON_ARGS+=(--attention-backend "$ATTENTION_BACKEND")
  fi
  if [[ -n "$KV_CACHE_DTYPE" ]]; then
    COMMON_ARGS+=(--kv-cache-dtype "$KV_CACHE_DTYPE")
  fi
  if [[ -n "$QUANTIZATION" ]]; then
    COMMON_ARGS+=(--quantization "$QUANTIZATION")
  fi
  if [[ -n "$CUDA_GRAPH_MAX_BS" ]]; then
    COMMON_ARGS+=(--cuda-graph-max-bs "$CUDA_GRAPH_MAX_BS")
  fi
  if [[ "$DISABLE_RADIX_CACHE" == "1" ]]; then
    COMMON_ARGS+=(--disable-radix-cache)
  fi
  if [[ "$DISABLE_CUDA_GRAPH" == "1" ]]; then
    COMMON_ARGS+=(--disable-cuda-graph)
  fi
  if [[ "$SKIP_SERVER_WARMUP" == "1" ]]; then
    COMMON_ARGS+=(--skip-server-warmup)
  fi
  if [[ -n "$TRANSFER_BACKEND" ]]; then
    COMMON_ARGS+=(--disaggregation-transfer-backend "$TRANSFER_BACKEND")
  fi
  if [[ -n "$DISAGG_IB_DEVICE" ]]; then
    COMMON_ARGS+=(--disaggregation-ib-device "$DISAGG_IB_DEVICE")
  fi
  if [[ "$ENABLE_DP_ATTENTION" == "1" ]]; then
    COMMON_ARGS+=(--enable-dp-attention)
  fi
}

wait_for_health() {
  local name="$1"
  local url="$2"
  local deadline=$((SECONDS + READY_TIMEOUT_SECS))

  echo "Waiting for ${name}: ${url}/health"
  until curl -fsS "${url}/health" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for ${name}. Check logs in ${LOG_DIR}."
      return 1
    fi
    sleep 10
  done
  echo "${name} is healthy."
}

launch_prefill_workers() {
  IFS=';' read -r -a groups <<< "$PREFILL_GROUPS"
  for idx in "${!groups[@]}"; do
    local group="${groups[$idx]// /}"
    [[ -z "$group" ]] && continue
    local port=$((PREFILL_PORT_START + idx))
    local bootstrap_port=$((BOOTSTRAP_PORT_START + idx))
    local tp_size="$PREFILL_TP_SIZE"
    if [[ "$tp_size" == "auto" ]]; then
      tp_size="$(count_gpus "$group")"
    fi

    add_common_server_args "$PREFILL_MEM_FRACTION_STATIC"
    args=(
      "${COMMON_ARGS[@]}"
      --disaggregation-mode prefill
      --port "$port"
      --tp-size "$tp_size"
      --disaggregation-bootstrap-port "$bootstrap_port"
    )
    if [[ -n "$PREFILL_DP_SIZE" ]]; then
      args+=(--dp-size "$PREFILL_DP_SIZE")
    fi
    if [[ -n "$PREFILL_MAX_RUNNING_REQUESTS" ]]; then
      args+=(--max-running-requests "$PREFILL_MAX_RUNNING_REQUESTS")
    fi
    while IFS= read -r -d '' word; do args+=("$word"); done < <(append_extra_args "$EXTRA_SERVER_ARGS")
    while IFS= read -r -d '' word; do args+=("$word"); done < <(append_extra_args "$PREFILL_EXTRA_ARGS")

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
    local tp_size="$DECODE_TP_SIZE"
    if [[ "$tp_size" == "auto" ]]; then
      tp_size="$(count_gpus "$group")"
    fi

    add_common_server_args "$DECODE_MEM_FRACTION_STATIC"
    args=(
      "${COMMON_ARGS[@]}"
      --disaggregation-mode decode
      --port "$port"
      --tp-size "$tp_size"
      --base-gpu-id 0
    )
    if [[ -n "$DECODE_DP_SIZE" ]]; then
      args+=(--dp-size "$DECODE_DP_SIZE")
    fi
    if [[ -n "$DECODE_MAX_RUNNING_REQUESTS" ]]; then
      args+=(--max-running-requests "$DECODE_MAX_RUNNING_REQUESTS")
    fi
    while IFS= read -r -d '' word; do args+=("$word"); done < <(append_extra_args "$EXTRA_SERVER_ARGS")
    while IFS= read -r -d '' word; do args+=("$word"); done < <(append_extra_args "$DECODE_EXTRA_ARGS")

    local log_file="${LOG_DIR}/decode_${idx}.log"
    echo "Starting decode worker ${idx}: GPUs=${group}, port=${port}, tp=${tp_size}"
    CUDA_VISIBLE_DEVICES="$group" nohup "$PYTHON_BIN" -m sglang.launch_server "${args[@]}" > "$log_file" 2>&1 &
    local pid=$!
    echo "$pid decode ${WORKER_ADDR}:${port} ${log_file}" >> "$PID_FILE"
    DECODE_URL_ARGS+=(--decode "http://${WORKER_ADDR}:${port}")
  done
}

launch_router() {
  args=(
    --pd-disaggregation
    --host "$ROUTER_HOST"
    --port "$ROUTER_PORT"
    --worker-startup-timeout-secs "$ROUTER_WORKER_STARTUP_TIMEOUT_SECS"
    --worker-startup-check-interval "$ROUTER_WORKER_STARTUP_CHECK_INTERVAL"
    --log-level "$ROUTER_LOG_LEVEL"
    --model-path "$MODEL_PATH"
    --tokenizer-path "$TOKENIZER_PATH"
  )

  if [[ -n "$PREFILL_POLICY" || -n "$DECODE_POLICY" ]]; then
    [[ -n "$PREFILL_POLICY" ]] && args+=(--prefill-policy "$PREFILL_POLICY")
    [[ -n "$DECODE_POLICY" ]] && args+=(--decode-policy "$DECODE_POLICY")
  else
    args+=(--policy "$ROUTER_POLICY")
  fi
  if [[ -n "$REASONING_PARSER" ]]; then
    args+=(--reasoning-parser "$REASONING_PARSER")
  fi
  while IFS= read -r -d '' word; do args+=("$word"); done < <(append_extra_args "$ROUTER_EXTRA_ARGS")

  local log_file="${LOG_DIR}/router.log"
  echo "Starting router: ${ROUTER_HOST}:${ROUTER_PORT}"
  nohup "$PYTHON_BIN" -m sglang_router.launch_router "${args[@]}" "${PREFILL_URL_ARGS[@]}" "${DECODE_URL_ARGS[@]}" > "$log_file" 2>&1 &
  local pid=$!
  echo "$pid router ${ROUTER_ADDR}:${ROUTER_PORT} ${log_file}" >> "$PID_FILE"
}

cd "$SGLANG_DIR"

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

if [[ "$WAIT_FOR_READY" == "1" ]]; then
  wait_for_health "router" "http://${ROUTER_ADDR}:${ROUTER_PORT}"
fi

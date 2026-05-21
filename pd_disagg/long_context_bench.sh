#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
timestamp="$(date +%Y%m%d_%H%M%S)"
run_dir="${LONG_CONTEXT_OUTPUT_DIR:-${LOG_DIR}/long_context_${timestamp}}"

LONG_CONTEXT_RANDOM_RANGE_RATIO="${LONG_CONTEXT_RANDOM_RANGE_RATIO:-0.5}"
LONG_CONTEXT_WARMUP_REQUESTS="${LONG_CONTEXT_WARMUP_REQUESTS:-2}"
LONG_CONTEXT_MONITOR_GPU="${LONG_CONTEXT_MONITOR_GPU:-1}"
LONG_CONTEXT_STOP_ON_FAILURE="${LONG_CONTEXT_STOP_ON_FAILURE:-1}"

if [[ "${LONG_CONTEXT_QUICK:-0}" == "1" ]]; then
  LONG_CONTEXT_REQUEST_RATES="${LONG_CONTEXT_REQUEST_RATES:-2 5}"
  LONG_CONTEXT_WORKLOADS="${LONG_CONTEXT_WORKLOADS:-4096:256}"
  LONG_CONTEXT_NUM_PROMPTS="${LONG_CONTEXT_NUM_PROMPTS:-50}"
  LONG_CONTEXT_MAX_CONCURRENCY="${LONG_CONTEXT_MAX_CONCURRENCY:-32}"
else
  LONG_CONTEXT_REQUEST_RATES="${LONG_CONTEXT_REQUEST_RATES:-2 5 10 20}"
  LONG_CONTEXT_WORKLOADS="${LONG_CONTEXT_WORKLOADS:-4096:256 8192:256 16384:256}"
  LONG_CONTEXT_NUM_PROMPTS="${LONG_CONTEXT_NUM_PROMPTS:-200}"
  LONG_CONTEXT_MAX_CONCURRENCY="${LONG_CONTEXT_MAX_CONCURRENCY:-64}"
fi

mkdir -p "$run_dir"

gpu_monitor_pid=""
stop_gpu_monitor() {
  if [[ -n "$gpu_monitor_pid" ]] && kill -0 "$gpu_monitor_pid" 2>/dev/null; then
    kill "$gpu_monitor_pid" 2>/dev/null || true
    wait "$gpu_monitor_pid" 2>/dev/null || true
  fi
}
trap stop_gpu_monitor EXIT

{
  echo "timestamp=${timestamp}"
  echo "request_rates=${LONG_CONTEXT_REQUEST_RATES}"
  echo "workloads=${LONG_CONTEXT_WORKLOADS}"
  echo "num_prompts=${LONG_CONTEXT_NUM_PROMPTS}"
  echo "max_concurrency=${LONG_CONTEXT_MAX_CONCURRENCY}"
  echo "random_range_ratio=${LONG_CONTEXT_RANDOM_RANGE_RATIO}"
  echo "warmup_requests=${LONG_CONTEXT_WARMUP_REQUESTS}"
  echo "monitor_gpu=${LONG_CONTEXT_MONITOR_GPU}"
  echo "stop_on_failure=${LONG_CONTEXT_STOP_ON_FAILURE}"
  echo "model_path=${MODEL_PATH:-/mnt/nvme3n1/g00872988/models/Qwen3-32B}"
  echo "base_url=${BASE_URL:-http://${ROUTER_ADDR:-127.0.0.1}:${ROUTER_PORT:-18080}}"
} > "${run_dir}/config.env"

if [[ "$LONG_CONTEXT_MONITOR_GPU" == "1" ]] && command -v nvidia-smi >/dev/null 2>&1; then
  echo "Starting GPU monitor: ${run_dir}/gpu_dmon.log"
  nvidia-smi dmon -s pucm -d 2 -o TD > "${run_dir}/gpu_dmon.log" 2>&1 &
  gpu_monitor_pid="$!"
  nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,utilization.memory \
    --format=csv > "${run_dir}/gpu_before.csv" 2>/dev/null || true
else
  echo "GPU monitor disabled or nvidia-smi not found."
fi

echo "Long-context benchmark output directory: ${run_dir}"
echo "Workloads: ${LONG_CONTEXT_WORKLOADS}"
echo "Request rates: ${LONG_CONTEXT_REQUEST_RATES}"
echo "Num prompts: ${LONG_CONTEXT_NUM_PROMPTS}"
echo "Max concurrency: ${LONG_CONTEXT_MAX_CONCURRENCY}"

SWEEP_REQUEST_RATES="$LONG_CONTEXT_REQUEST_RATES" \
SWEEP_WORKLOADS="$LONG_CONTEXT_WORKLOADS" \
SWEEP_NUM_PROMPTS="$LONG_CONTEXT_NUM_PROMPTS" \
SWEEP_MAX_CONCURRENCY="$LONG_CONTEXT_MAX_CONCURRENCY" \
SWEEP_RANDOM_RANGE_RATIO="$LONG_CONTEXT_RANDOM_RANGE_RATIO" \
SWEEP_WARMUP_REQUESTS="$LONG_CONTEXT_WARMUP_REQUESTS" \
SWEEP_STOP_ON_FAILURE="$LONG_CONTEXT_STOP_ON_FAILURE" \
SWEEP_OUTPUT_DIR="$run_dir" \
"${SCRIPT_DIR}/sweep_bench.sh"

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,utilization.memory \
    --format=csv > "${run_dir}/gpu_after.csv" 2>/dev/null || true
fi

summary_file="${run_dir}/summary.tsv"
echo
echo "Long-context benchmark complete."
echo "Summary: ${summary_file}"
echo "GPU monitor log: ${run_dir}/gpu_dmon.log"

if [[ -f "$summary_file" ]]; then
  echo
  echo "Read guide:"
  echo "- TTFT rises with input length: prefill or queue pressure."
  echo "- TPOT rises while TTFT is stable: decode pressure."
  echo "- Throughput stops rising before target request rate: capacity limit."
  echo "- GPU memory close to full or failures: reduce concurrency or max context."
fi

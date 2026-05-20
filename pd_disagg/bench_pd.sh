#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python3}"
MODEL_PATH="${MODEL_PATH:-/mnt/nvme3n1/g00872988/models/Qwen3-8B}"
TOKENIZER_PATH="${TOKENIZER_PATH:-$MODEL_PATH}"
ROUTER_ADDR="${ROUTER_ADDR:-127.0.0.1}"
ROUTER_PORT="${ROUTER_PORT:-18080}"
BASE_URL="${BASE_URL:-http://${ROUTER_ADDR}:${ROUTER_PORT}}"
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
mkdir -p "$LOG_DIR"

BENCH_BACKEND="${BENCH_BACKEND:-sglang}"
BENCH_DATASET_NAME="${BENCH_DATASET_NAME:-random}"
BENCH_NUM_PROMPTS="${BENCH_NUM_PROMPTS:-200}"
BENCH_RANDOM_INPUT_LEN="${BENCH_RANDOM_INPUT_LEN:-2048}"
BENCH_RANDOM_OUTPUT_LEN="${BENCH_RANDOM_OUTPUT_LEN:-256}"
BENCH_RANDOM_RANGE_RATIO="${BENCH_RANDOM_RANGE_RATIO:-0.5}"
BENCH_REQUEST_RATE="${BENCH_REQUEST_RATE:-10}"
BENCH_MAX_CONCURRENCY="${BENCH_MAX_CONCURRENCY:-64}"
BENCH_WARMUP_REQUESTS="${BENCH_WARMUP_REQUESTS:-2}"
BENCH_OUTPUT_DETAILS="${BENCH_OUTPUT_DETAILS:-1}"
BENCH_EXTRA_ARGS="${BENCH_EXTRA_ARGS:-}"

timestamp="$(date +%Y%m%d_%H%M%S)"
output_file="${BENCH_OUTPUT_FILE:-${LOG_DIR}/bench_pd_${timestamp}.jsonl}"

if [[ -n "${SGLANG_DIR:-}" ]]; then
  if [[ ! -d "$SGLANG_DIR" ]]; then
    echo "SGLANG_DIR does not exist: ${SGLANG_DIR}"
    exit 1
  fi
  export PYTHONPATH="${SGLANG_DIR}/python:${SGLANG_DIR}/sgl-model-gateway/bindings/python/src:${PYTHONPATH:-}"
fi

args=(
  -m sglang.bench_serving
  --backend "$BENCH_BACKEND"
  --base-url "$BASE_URL"
  --model "$MODEL_PATH"
  --tokenizer "$TOKENIZER_PATH"
  --dataset-name "$BENCH_DATASET_NAME"
  --num-prompts "$BENCH_NUM_PROMPTS"
  --random-input-len "$BENCH_RANDOM_INPUT_LEN"
  --random-output-len "$BENCH_RANDOM_OUTPUT_LEN"
  --random-range-ratio "$BENCH_RANDOM_RANGE_RATIO"
  --request-rate "$BENCH_REQUEST_RATE"
  --max-concurrency "$BENCH_MAX_CONCURRENCY"
  --warmup-requests "$BENCH_WARMUP_REQUESTS"
  --output-file "$output_file"
)

if [[ "$BENCH_OUTPUT_DETAILS" == "1" ]]; then
  args+=(--output-details)
fi
if [[ -n "$BENCH_EXTRA_ARGS" ]]; then
  # Intentional word splitting for simple extra CLI flags.
  # shellcheck disable=SC2206
  extra_words=( $BENCH_EXTRA_ARGS )
  args+=("${extra_words[@]}")
fi

echo "Benchmarking ${BASE_URL}"
echo "Writing JSONL metrics to ${output_file}"
"$PYTHON_BIN" "${args[@]}"

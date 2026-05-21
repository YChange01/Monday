#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

PYTHON_BIN="${PYTHON_BIN:-python3}"
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
timestamp="$(date +%Y%m%d_%H%M%S)"

PROFILE_TARGET="${PROFILE_TARGET:-prefill}" # prefill, decode, or both
PROFILE_WORKLOAD="${PROFILE_WORKLOAD:-2048:256}"
PROFILE_REQUEST_RATE="${PROFILE_REQUEST_RATE:-40}"
PROFILE_NUM_PROMPTS="${PROFILE_NUM_PROMPTS:-100}"
PROFILE_MAX_CONCURRENCY="${PROFILE_MAX_CONCURRENCY:-64}"
PROFILE_RANDOM_RANGE_RATIO="${PROFILE_RANDOM_RANGE_RATIO:-0.5}"
PROFILE_WARMUP_REQUESTS="${PROFILE_WARMUP_REQUESTS:-2}"
PROFILE_STEPS="${PROFILE_STEPS:-20}"
PROFILE_ACTIVITIES="${PROFILE_ACTIVITIES:-CPU GPU}"
PROFILE_PREFILL_URLS="${PROFILE_PREFILL_URLS:-http://127.0.0.1:18100}"
PROFILE_DECODE_URLS="${PROFILE_DECODE_URLS:-http://127.0.0.1:18200}"
PROFILE_CONVERT_TABLES="${PROFILE_CONVERT_TABLES:-1}"
PROFILE_XLSX="${PROFILE_XLSX:-1}"
PROFILE_OUTPUT_ROOT="${PROFILE_OUTPUT_ROOT:-${LOG_DIR}/profile_${timestamp}}"

case "$PROFILE_TARGET" in
  prefill|decode|both) ;;
  *)
    echo "PROFILE_TARGET must be one of: prefill, decode, both"
    exit 1
    ;;
esac

if [[ "$PROFILE_WORKLOAD" != *:* ]]; then
  echo "PROFILE_WORKLOAD must use input_len:output_len, for example 2048:256."
  exit 1
fi

input_len="${PROFILE_WORKLOAD%%:*}"
output_len="${PROFILE_WORKLOAD##*:}"
mkdir -p "$PROFILE_OUTPUT_ROOT"

run_profile_target() {
  local target="$1"
  local stage="$2"
  local urls="$3"
  local output_dir="${PROFILE_OUTPUT_ROOT}/${target}"
  local prefix="${target}_i${input_len}_o${output_len}_r${PROFILE_REQUEST_RATE}"
  local extra_args

  mkdir -p "$output_dir"

  extra_args="--profile --pd-separated"
  extra_args+=" --profile-output-dir ${output_dir}"
  extra_args+=" --profile-prefix ${prefix}"
  extra_args+=" --profile-by-stage --profile-stages ${stage}"
  extra_args+=" --profile-activities ${PROFILE_ACTIVITIES}"
  extra_args+=" --profile-steps ${PROFILE_STEPS}"

  if [[ "$target" == "prefill" ]]; then
    extra_args+=" --profile-prefill-url ${urls}"
  else
    extra_args+=" --profile-decode-url ${urls}"
  fi

  echo
  echo "=== Profiling ${target} ==="
  echo "Workload: ${PROFILE_WORKLOAD}"
  echo "Request rate: ${PROFILE_REQUEST_RATE}"
  echo "Max concurrency: ${PROFILE_MAX_CONCURRENCY}"
  echo "Profile steps: ${PROFILE_STEPS}"
  echo "Activities: ${PROFILE_ACTIVITIES}"
  echo "Worker URLs: ${urls}"
  echo "Output dir: ${output_dir}"

  BENCH_NUM_PROMPTS="$PROFILE_NUM_PROMPTS" \
  BENCH_RANDOM_INPUT_LEN="$input_len" \
  BENCH_RANDOM_OUTPUT_LEN="$output_len" \
  BENCH_RANDOM_RANGE_RATIO="$PROFILE_RANDOM_RANGE_RATIO" \
  BENCH_REQUEST_RATE="$PROFILE_REQUEST_RATE" \
  BENCH_MAX_CONCURRENCY="$PROFILE_MAX_CONCURRENCY" \
  BENCH_WARMUP_REQUESTS="$PROFILE_WARMUP_REQUESTS" \
  BENCH_OUTPUT_FILE="${output_dir}/${prefix}.jsonl" \
  BENCH_EXTRA_ARGS="$extra_args" \
  "${SCRIPT_DIR}/bench_pd.sh" 2>&1 | tee "${output_dir}/${prefix}.log"

  if [[ "$PROFILE_CONVERT_TABLES" == "1" ]]; then
    convert_traces "$output_dir"
  fi
}

convert_traces() {
  local output_dir="$1"
  local trace
  local trace_name
  local table_dir
  local found=0

  if [[ ! -f "${SCRIPT_DIR}/trace_to_table.py" ]]; then
    echo "trace_to_table.py not found; skipping table conversion."
    return
  fi

  while IFS= read -r trace; do
    found=1
    trace_name="$(basename "$trace")"
    trace_name="${trace_name%.gz}"
    trace_name="${trace_name%.json}"
    trace_name="${trace_name%.trace}"
    table_dir="${output_dir}/tables/${trace_name}"

    echo
    echo "Converting trace to tables: ${trace}"
    convert_args=("${SCRIPT_DIR}/trace_to_table.py" "$trace" "--out-dir" "$table_dir")
    if [[ "$PROFILE_XLSX" == "1" ]]; then
      convert_args+=("--xlsx")
    fi
    "$PYTHON_BIN" "${convert_args[@]}"
  done < <(find "$output_dir" -type f \( -name "*.trace.json" -o -name "*.trace.json.gz" -o -name "*.json.gz" \) | sort)

  if [[ "$found" == "0" ]]; then
    echo "No trace files found under ${output_dir}; table conversion skipped."
  fi
}

echo "Profile output root: ${PROFILE_OUTPUT_ROOT}"

case "$PROFILE_TARGET" in
  prefill)
    run_profile_target "prefill" "prefill" "$PROFILE_PREFILL_URLS"
    ;;
  decode)
    run_profile_target "decode" "decode" "$PROFILE_DECODE_URLS"
    ;;
  both)
    run_profile_target "prefill" "prefill" "$PROFILE_PREFILL_URLS"
    run_profile_target "decode" "decode" "$PROFILE_DECODE_URLS"
    ;;
esac

echo
echo "Profiling complete."
echo "Output root: ${PROFILE_OUTPUT_ROOT}"

#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

SWEEP_REQUEST_RATES="${SWEEP_REQUEST_RATES:-10 20 40 80}"
SWEEP_WORKLOADS="${SWEEP_WORKLOADS:-2048:256}"
SWEEP_NUM_PROMPTS="${SWEEP_NUM_PROMPTS:-500}"
SWEEP_MAX_CONCURRENCY="${SWEEP_MAX_CONCURRENCY:-128}"
SWEEP_RANDOM_RANGE_RATIO="${SWEEP_RANDOM_RANGE_RATIO:-0.5}"
SWEEP_WARMUP_REQUESTS="${SWEEP_WARMUP_REQUESTS:-2}"
SWEEP_STOP_ON_FAILURE="${SWEEP_STOP_ON_FAILURE:-1}"

BENCH_DATASET_NAME="${BENCH_DATASET_NAME:-random-ids}"
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"

timestamp="$(date +%Y%m%d_%H%M%S)"
run_dir="${SWEEP_OUTPUT_DIR:-${LOG_DIR}/sweep_${timestamp}}"
summary_file="${run_dir}/summary.tsv"

mkdir -p "$run_dir"

metric() {
  local key="$1"
  local file="$2"
  awk -F: -v key="$key" '
    $1 == key {
      value = $2
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      print value
      exit
    }
  ' "$file"
}

write_summary_header() {
  printf '%s\t' \
    workload request_rate max_concurrency num_prompts status \
    successful_requests duration_s req_throughput input_tok_s output_tok_s \
    total_tok_s concurrency mean_e2e_ms p99_e2e_ms mean_ttft_ms p99_ttft_ms \
    mean_tpot_ms p99_tpot_ms
  printf '%s\t%s\n' log_file metrics_file
}

append_summary_row() {
  local workload="$1"
  local request_rate="$2"
  local max_concurrency="$3"
  local num_prompts="$4"
  local status="$5"
  local log_file="$6"
  local metrics_file="$7"

  printf '%s\t%s\t%s\t%s\t%s\t' \
    "$workload" "$request_rate" "$max_concurrency" "$num_prompts" "$status"

  if [[ "$status" == "ok" ]]; then
    printf '%s\t' \
      "$(metric "Successful requests" "$log_file")" \
      "$(metric "Benchmark duration (s)" "$log_file")" \
      "$(metric "Request throughput (req/s)" "$log_file")" \
      "$(metric "Input token throughput (tok/s)" "$log_file")" \
      "$(metric "Output token throughput (tok/s)" "$log_file")" \
      "$(metric "Total token throughput (tok/s)" "$log_file")" \
      "$(metric "Concurrency" "$log_file")" \
      "$(metric "Mean E2E Latency (ms)" "$log_file")" \
      "$(metric "P99 E2E Latency (ms)" "$log_file")" \
      "$(metric "Mean TTFT (ms)" "$log_file")" \
      "$(metric "P99 TTFT (ms)" "$log_file")" \
      "$(metric "Mean TPOT (ms)" "$log_file")" \
      "$(metric "P99 TPOT (ms)" "$log_file")"
  else
    printf '\t\t\t\t\t\t\t\t\t\t\t\t\t'
  fi

  printf '%s\t%s\n' "$log_file" "$metrics_file"
}

write_summary_header > "$summary_file"

echo "Sweep output directory: ${run_dir}"
echo "Summary: ${summary_file}"
echo "Workloads: ${SWEEP_WORKLOADS}"
echo "Request rates: ${SWEEP_REQUEST_RATES}"
echo "Dataset: ${BENCH_DATASET_NAME}"

for workload in $SWEEP_WORKLOADS; do
  input_len="${workload%%:*}"
  output_len="${workload##*:}"

  if [[ "$input_len" == "$output_len" && "$workload" != *:* ]]; then
    echo "Invalid workload '${workload}'. Use input_len:output_len, for example 2048:256."
    exit 1
  fi

  for request_rate in $SWEEP_REQUEST_RATES; do
    safe_rate="${request_rate//[^A-Za-z0-9_.-]/_}"
    log_file="${run_dir}/bench_i${input_len}_o${output_len}_r${safe_rate}.log"
    metrics_file="${run_dir}/bench_i${input_len}_o${output_len}_r${safe_rate}.jsonl"

    echo
    echo "=== workload=${input_len}:${output_len} request_rate=${request_rate} max_concurrency=${SWEEP_MAX_CONCURRENCY} ==="

    set +e
    BENCH_DATASET_NAME="$BENCH_DATASET_NAME" \
      BENCH_NUM_PROMPTS="$SWEEP_NUM_PROMPTS" \
      BENCH_RANDOM_INPUT_LEN="$input_len" \
      BENCH_RANDOM_OUTPUT_LEN="$output_len" \
      BENCH_RANDOM_RANGE_RATIO="$SWEEP_RANDOM_RANGE_RATIO" \
      BENCH_REQUEST_RATE="$request_rate" \
      BENCH_MAX_CONCURRENCY="$SWEEP_MAX_CONCURRENCY" \
      BENCH_WARMUP_REQUESTS="$SWEEP_WARMUP_REQUESTS" \
      BENCH_OUTPUT_FILE="$metrics_file" \
      "${SCRIPT_DIR}/bench_pd.sh" 2>&1 | tee "$log_file"
    bench_status="${PIPESTATUS[0]}"
    set -e

    if [[ "$bench_status" -eq 0 ]]; then
      append_summary_row "$workload" "$request_rate" "$SWEEP_MAX_CONCURRENCY" \
        "$SWEEP_NUM_PROMPTS" "ok" "$log_file" "$metrics_file" >> "$summary_file"
    else
      append_summary_row "$workload" "$request_rate" "$SWEEP_MAX_CONCURRENCY" \
        "$SWEEP_NUM_PROMPTS" "failed" "$log_file" "$metrics_file" >> "$summary_file"
      echo "Benchmark failed at workload=${workload}, request_rate=${request_rate}."
      if [[ "$SWEEP_STOP_ON_FAILURE" == "1" ]]; then
        echo "Stopping sweep because SWEEP_STOP_ON_FAILURE=1."
        break 2
      fi
    fi
  done
done

echo
echo "Sweep complete."
echo "Summary: ${summary_file}"
column -t -s $'\t' "$summary_file" || cat "$summary_file"

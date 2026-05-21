# SGLang PD Disaggregation for Qwen3-32B on B200

This directory contains launch scripts for a first B200 bring-up of SGLang
prefill/decode disaggregation with `/mnt/nvme3n1/g00872988/models/Qwen3-32B`.

## Files

- `start_pd.sh`: launches prefill workers, decode workers, and the router.
  Runtime defaults are defined here.
- `smoke_test.sh`: sends one request through the router.
- `bench_pd.sh`: runs `python -m sglang.bench_serving` against the router.
- `sweep_bench.sh`: runs a request-rate sweep against the current router.
- `profile_pd.sh`: runs prefill/decode profiling and converts traces to tables.
- `trace_to_table.py`: converts SGLang profiler traces into CSV/XLSX tables.
- `stop_pd.sh`: stops processes recorded in the PID file.

## Quick Start on B200

```bash
cd pd_disagg
# Make sure sglang, sglang-router, and nixl are installed in the active env.

./start_pd.sh
./smoke_test.sh
./bench_pd.sh
./stop_pd.sh
```

`start_pd.sh` returns only after the router health check and one minimal
end-to-end `/generate` request both succeed.
`smoke_test.sh` also defaults to a short probe request. Increase
`SMOKE_MAX_NEW_TOKENS` only after the short request is stable.

If the shell has HTTP proxy variables set, the launcher automatically adds
localhost addresses to `NO_PROXY`/`no_proxy` so prefill, decode, and bootstrap
traffic stays on the machine.

Default topology:

```bash
PREFILL_GROUPS="0;1"
DECODE_GROUPS="2;3"
```

That starts four full model replicas: two prefill workers and two decode
workers, each on one B200. Tensor parallel size is inferred from the number of
GPUs in each group.

Default ports:

```bash
ROUTER_PORT="18080"
PREFILL_PORT_START="18100"
DECODE_PORT_START="18200"
BOOTSTRAP_PORT_START="18300"
```

## Scaling Examples

Two TP=2 workers:

```bash
export PREFILL_GROUPS="0,1"
export DECODE_GROUPS="2,3"
```

Two prefill workers and two decode workers:

```bash
export PREFILL_GROUPS="0;1"
export DECODE_GROUPS="2;3"
```

## Transfer Notes

The launcher defaults to NIXL for single-node B200 bring-up:

```bash
export TRANSFER_BACKEND=nixl
export SGLANG_DISAGGREGATION_NIXL_BACKEND=UCX
```

If `nixl` is not installed, install it in the same Python environment used by
`PYTHON_BIN`, for example:

```bash
pip install nixl
```

Mooncake remains available as a fallback, but it requires the RDMA/NVLink
transfer path to be healthy on the host:

```bash
export TRANSFER_BACKEND=mooncake
```

## Initial Tuning Guidance

Start with BF16 and native 32K context:

```bash
export DTYPE=bfloat16
export CONTEXT_LENGTH=32768
```

Only move to FP8/quantized weights after the PD path is stable. First measure a
small grid of prompt/output lengths, for example:

```bash
BENCH_RANDOM_INPUT_LEN=1024  BENCH_RANDOM_OUTPUT_LEN=256 ./bench_pd.sh
BENCH_RANDOM_INPUT_LEN=4096  BENCH_RANDOM_OUTPUT_LEN=512 ./bench_pd.sh
BENCH_RANDOM_INPUT_LEN=8192  BENCH_RANDOM_OUTPUT_LEN=1024 ./bench_pd.sh
```

Watch TTFT, TPOT, transfer errors, GPU memory headroom, and router retries. If
decode TPOT spikes, add decode capacity or lower benchmark concurrency. If TTFT
is too high and decode is idle, add prefill capacity.

`bench_pd.sh` defaults to `BENCH_DATASET_NAME=random-ids` so it does not need to
download a ShareGPT file from Hugging Face. Use `BENCH_DATASET_NAME=random` only
when the dataset is already cached or the host has working external access.

For an automatic request-rate sweep against the current running topology:

```bash
SWEEP_REQUEST_RATES="10 20 40 80" \
SWEEP_WORKLOADS="2048:256" \
SWEEP_NUM_PROMPTS=500 \
SWEEP_MAX_CONCURRENCY=128 \
./sweep_bench.sh
```

The sweep writes per-run logs plus a tab-separated summary under
`logs/sweep_<timestamp>/`. To compare topologies, start one topology, run the
sweep, stop it, start the next topology, and run the sweep again.

## Profiling Trace Tables

To capture a profiling run and convert the trace into tables:

```bash
# Prefill only, one worker by default.
./profile_pd.sh

# Decode only.
PROFILE_TARGET=decode ./profile_pd.sh

# Both sides, profiled as separate benchmark runs.
PROFILE_TARGET=both ./profile_pd.sh
```

Useful overrides:

```bash
PROFILE_WORKLOAD="2048:256" \
PROFILE_REQUEST_RATE=40 \
PROFILE_STEPS=20 \
PROFILE_PREFILL_URLS="http://127.0.0.1:18100 http://127.0.0.1:18101" \
PROFILE_TARGET=prefill \
./profile_pd.sh
```

The script writes traces, benchmark logs, JSONL metrics, and converted tables
under `logs/profile_<timestamp>/`.

Chrome tracing is useful for timelines, but the fastest way to inspect concrete
operations is to convert the trace to tables:

```bash
python trace_to_table.py \
  logs/profile_prefill_r40/<timestamp>/prefill_r40-*.trace.json.gz \
  --out-dir logs/profile_prefill_r40_tables \
  --xlsx
```

The script writes:

- `*_summary_by_name.csv`: operations ranked by total duration.
- `*_summary_by_stream.csv`: stream/thread totals and top operations.
- `*_long_events.csv`: longest individual events.
- `*_events.csv`: full event detail table.
- `*_trace_summary.xlsx`: Excel workbook, if `pandas` and `openpyxl` exist.

If the detail table is too large, filter short events:

```bash
python trace_to_table.py TRACE.trace.json.gz --min-dur-us 50 --xlsx
```

Start bottleneck analysis from `summary_by_name` and `summary_by_stream`.
`gemm`, `matmul`, `attention`, or `trtllm` at the top usually means GPU compute
is dominant. `memcpy`, `copy`, `transfer`, `nixl`, `ucx`, `wait`, or
`synchronize` near the top points to data movement or synchronization.

## References

- SGLang PD docs: https://docs.sglang.io/distributed/prefill-decode-disaggregation
- SGLang gateway docs: https://docs.sglang.io/advanced_features/sgl_model_gateway.html
- SGLang bench serving docs: https://docs.sglang.io/developer_guide/bench_serving.html
- Qwen3-32B model card: https://huggingface.co/Qwen/Qwen3-32B

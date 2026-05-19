# SGLang PD Disaggregation for Qwen3-32B on B200

This directory contains launch scripts for a first B200 bring-up of SGLang
prefill/decode disaggregation with `Qwen/Qwen3-32B`.

The SGLang source is cloned at `../sglang`. The local checkout used when these
scripts were created was commit `87c3c96`.

## Files

- `env.b200.example.sh`: editable configuration template.
- `setup_b200_env.sh`: creates a Python virtualenv and installs SGLang, router,
  and transfer dependencies.
- `start_pd_qwen3_32b.sh`: launches prefill workers, decode workers, and the
  router.
- `smoke_test.sh`: sends one request through the router.
- `bench_pd.sh`: runs `python -m sglang.bench_serving` against the router.
- `stop_pd.sh`: stops processes recorded in the PID file.

## Quick Start on B200

```bash
cd pd_disagg
cp env.b200.example.sh env.b200.local.sh
# Edit env.b200.local.sh for GPU groups, IB/NVLink, ports, and model cache.

./setup_b200_env.sh
source .venv/bin/activate

./start_pd_qwen3_32b.sh
./smoke_test.sh
./bench_pd.sh
./stop_pd.sh
```

Default topology:

```bash
PREFILL_GROUPS="0"
DECODE_GROUPS="1"
PREFILL_TP_SIZE="auto"
DECODE_TP_SIZE="auto"
```

That starts two full model replicas, one for prefill and one for decode. Use at
least two B200 GPUs for the initial real PD test. A single GPU can be useful for
syntax experiments only, but it is not a representative PD setup because both
roles duplicate model weights and compete for KV memory.

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

If prefill and decode use different TP layouts, enable the staging buffer:

```bash
export ENABLE_STAGING_BUFFER=1
```

## Transfer Notes

The default backend is Mooncake:

```bash
export TRANSFER_BACKEND=mooncake
```

For single-node NVLink, try:

```bash
export MOONCAKE_MEM_POOL=INTRA_NODE_NVLINK
```

For NVL rack-scale deployments, use:

```bash
export MOONCAKE_MEM_POOL=NVLINK
```

For multi-node RDMA/RoCE, set the exact IB devices after verifying them with
`ibstat` or `ibv_devinfo`:

```bash
export DISAGG_IB_DEVICE=mlx5_0
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
decode TPOT spikes, lower `DECODE_MAX_RUNNING_REQUESTS` first. If TTFT is too
high and decode is idle, add prefill capacity or tune chunked prefill.

## References

- SGLang PD docs: https://docs.sglang.io/distributed/prefill-decode-disaggregation
- SGLang gateway docs: https://docs.sglang.io/advanced_features/sgl_model_gateway.html
- SGLang bench serving docs: https://docs.sglang.io/developer_guide/bench_serving.html
- Qwen3-32B model card: https://huggingface.co/Qwen/Qwen3-32B

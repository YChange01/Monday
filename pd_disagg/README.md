# SGLang PD Disaggregation for Qwen3-8B on B200

This directory contains launch scripts for a first B200 bring-up of SGLang
prefill/decode disaggregation with `/mnt/nvme3n1/g00872988/models/Qwen3-8B`.

## Files

- `start_pd.sh`: launches prefill workers, decode workers, and the router.
  Runtime defaults are defined here.
- `smoke_test.sh`: sends one request through the router.
- `bench_pd.sh`: runs `python -m sglang.bench_serving` against the router.
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

If the shell has HTTP proxy variables set, the launcher automatically adds
localhost addresses to `NO_PROXY`/`no_proxy` so prefill, decode, and bootstrap
traffic stays on the machine.

Default topology:

```bash
PREFILL_GROUPS="4"
DECODE_GROUPS="5"
```

That starts two full model replicas, one for prefill and one for decode. Tensor
parallel size is inferred from the number of GPUs in each group. Use at least
two B200 GPUs for the initial real PD test. A single GPU can be useful for syntax
experiments only, but it is not a representative PD setup because both roles
duplicate model weights and compete for KV memory.

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

## References

- SGLang PD docs: https://docs.sglang.io/distributed/prefill-decode-disaggregation
- SGLang gateway docs: https://docs.sglang.io/advanced_features/sgl_model_gateway.html
- SGLang bench serving docs: https://docs.sglang.io/developer_guide/bench_serving.html
- Qwen3-8B model card: https://huggingface.co/Qwen/Qwen3-8B

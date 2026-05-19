# Copy this file to env.b200.local.sh and edit it on the B200 machine.
# The launcher sources env.b200.local.sh first when it exists.

# Leave empty to use ../sglang relative to this directory.
export SGLANG_DIR="${SGLANG_DIR:-}"
export PYTHON_BIN="${PYTHON_BIN:-python3}"

# Qwen3-32B defaults.
export MODEL_PATH="${MODEL_PATH:-Qwen/Qwen3-32B}"
export TOKENIZER_PATH="${TOKENIZER_PATH:-$MODEL_PATH}"
export SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3-32b}"
export REASONING_PARSER="${REASONING_PARSER:-qwen3}"
export TRUST_REMOTE_CODE="${TRUST_REMOTE_CODE:-1}"

# Single-node minimum PD topology: one full prefill worker on GPU 0 and
# one full decode worker on GPU 1. Use semicolons for multiple workers,
# for example: PREFILL_GROUPS="0;1" DECODE_GROUPS="2;3"
# For tensor parallel workers, use comma-separated groups:
# PREFILL_GROUPS="0,1" DECODE_GROUPS="2,3"
export PREFILL_GROUPS="${PREFILL_GROUPS:-0}"
export DECODE_GROUPS="${DECODE_GROUPS:-1}"
export PREFILL_TP_SIZE="${PREFILL_TP_SIZE:-auto}"
export DECODE_TP_SIZE="${DECODE_TP_SIZE:-auto}"

# Network layout. WORKER_HOST is the bind address. WORKER_ADDR is the address
# the router uses to reach workers.
export WORKER_HOST="${WORKER_HOST:-0.0.0.0}"
export WORKER_ADDR="${WORKER_ADDR:-127.0.0.1}"
export ROUTER_HOST="${ROUTER_HOST:-0.0.0.0}"
export ROUTER_ADDR="${ROUTER_ADDR:-127.0.0.1}"
export ROUTER_PORT="${ROUTER_PORT:-8000}"
export PREFILL_PORT_START="${PREFILL_PORT_START:-30000}"
export DECODE_PORT_START="${DECODE_PORT_START:-30010}"
export BOOTSTRAP_PORT_START="${BOOTSTRAP_PORT_START:-8998}"

# Transfer backend. Mooncake is SGLang's default PD backend.
export TRANSFER_BACKEND="${TRANSFER_BACKEND:-mooncake}"
export DISAGG_IB_DEVICE="${DISAGG_IB_DEVICE:-}"

# Set one of these on NVLink machines if applicable:
#   MOONCAKE_MEM_POOL=INTRA_NODE_NVLINK  for intra-node NVLink
#   MOONCAKE_MEM_POOL=NVLINK             for NVL rack-scale deployments
export MOONCAKE_MEM_POOL="${MOONCAKE_MEM_POOL:-}"

# Enable only when prefill and decode use different TP layouts.
export ENABLE_STAGING_BUFFER="${ENABLE_STAGING_BUFFER:-0}"
export STAGING_BUFFER_SIZE_MB="${STAGING_BUFFER_SIZE_MB:-64}"
export STAGING_POOL_SIZE_MB="${STAGING_POOL_SIZE_MB:-4096}"

# Conservative memory defaults for a first B200 bring-up. Tune after the
# smoke test succeeds.
export DTYPE="${DTYPE:-bfloat16}"
export CONTEXT_LENGTH="${CONTEXT_LENGTH:-32768}"
export PREFILL_MEM_FRACTION_STATIC="${PREFILL_MEM_FRACTION_STATIC:-0.78}"
export DECODE_MEM_FRACTION_STATIC="${DECODE_MEM_FRACTION_STATIC:-0.86}"
export CHUNKED_PREFILL_SIZE="${CHUNKED_PREFILL_SIZE:-}"
export PREFILL_MAX_RUNNING_REQUESTS="${PREFILL_MAX_RUNNING_REQUESTS:-}"
export DECODE_MAX_RUNNING_REQUESTS="${DECODE_MAX_RUNNING_REQUESTS:-128}"
export CUDA_GRAPH_MAX_BS="${CUDA_GRAPH_MAX_BS:-}"
export ATTENTION_BACKEND="${ATTENTION_BACKEND:-}"
export KV_CACHE_DTYPE="${KV_CACHE_DTYPE:-}"
export QUANTIZATION="${QUANTIZATION:-}"
export DISABLE_RADIX_CACHE="${DISABLE_RADIX_CACHE:-0}"
export DISABLE_CUDA_GRAPH="${DISABLE_CUDA_GRAPH:-0}"
export SKIP_SERVER_WARMUP="${SKIP_SERVER_WARMUP:-0}"

# Dense Qwen3-32B should start without DP attention. Keep this disabled unless
# you are testing a supported layout and know why it is needed.
export ENABLE_DP_ATTENTION="${ENABLE_DP_ATTENTION:-0}"
export PREFILL_DP_SIZE="${PREFILL_DP_SIZE:-}"
export DECODE_DP_SIZE="${DECODE_DP_SIZE:-}"

# Timeouts are intentionally relaxed for large-model first-token latency.
export SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT="${SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT:-600}"
export SGLANG_DISAGGREGATION_WAITING_TIMEOUT="${SGLANG_DISAGGREGATION_WAITING_TIMEOUT:-600}"
export ROUTER_WORKER_STARTUP_TIMEOUT_SECS="${ROUTER_WORKER_STARTUP_TIMEOUT_SECS:-1800}"
export ROUTER_WORKER_STARTUP_CHECK_INTERVAL="${ROUTER_WORKER_STARTUP_CHECK_INTERVAL:-30}"
export ROUTER_POLICY="${ROUTER_POLICY:-cache_aware}"
export PREFILL_POLICY="${PREFILL_POLICY:-cache_aware}"
export DECODE_POLICY="${DECODE_POLICY:-power_of_two}"
export ROUTER_LOG_LEVEL="${ROUTER_LOG_LEVEL:-info}"

# Optional raw extra arguments. These are split on spaces.
export EXTRA_SERVER_ARGS="${EXTRA_SERVER_ARGS:-}"
export PREFILL_EXTRA_ARGS="${PREFILL_EXTRA_ARGS:-}"
export DECODE_EXTRA_ARGS="${DECODE_EXTRA_ARGS:-}"
export ROUTER_EXTRA_ARGS="${ROUTER_EXTRA_ARGS:-}"

export LOG_DIR="${LOG_DIR:-}"
export PID_FILE="${PID_FILE:-}"
export WAIT_FOR_READY="${WAIT_FOR_READY:-1}"
export READY_TIMEOUT_SECS="${READY_TIMEOUT_SECS:-1800}"

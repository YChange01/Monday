# Copy this file to env.b200.local.sh and edit it on the B200 machine.
# The launcher sources env.b200.local.sh first when it exists.

# Use your manually prepared Python environment.
export PYTHON_BIN="${PYTHON_BIN:-python3}"

# Leave empty when sglang is installed as a Python package. Set this only when
# running from a local SGLang source checkout.
export SGLANG_DIR="${SGLANG_DIR:-}"

# Model.
export MODEL_PATH="${MODEL_PATH:-Qwen/Qwen3-32B}"
export TOKENIZER_PATH="${TOKENIZER_PATH:-$MODEL_PATH}"
export SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3-32b}"

# GPU topology. Commas mean tensor parallel inside one worker; semicolons mean
# multiple workers. Examples: "0,1" for TP=2, or "0;1" for two workers.
export PREFILL_GROUPS="${PREFILL_GROUPS:-0}"
export DECODE_GROUPS="${DECODE_GROUPS:-1}"
export PREFILL_TP_SIZE="${PREFILL_TP_SIZE:-auto}"
export DECODE_TP_SIZE="${DECODE_TP_SIZE:-auto}"

# Network.
export WORKER_HOST="${WORKER_HOST:-0.0.0.0}"
export WORKER_ADDR="${WORKER_ADDR:-127.0.0.1}"
export ROUTER_HOST="${ROUTER_HOST:-0.0.0.0}"
export ROUTER_ADDR="${ROUTER_ADDR:-127.0.0.1}"
export ROUTER_PORT="${ROUTER_PORT:-8000}"
export PREFILL_PORT_START="${PREFILL_PORT_START:-30000}"
export DECODE_PORT_START="${DECODE_PORT_START:-30010}"
export BOOTSTRAP_PORT_START="${BOOTSTRAP_PORT_START:-8998}"

# KV transfer.
export TRANSFER_BACKEND="${TRANSFER_BACKEND:-mooncake}"
export DISAGG_IB_DEVICE="${DISAGG_IB_DEVICE:-}"
export MOONCAKE_MEM_POOL="${MOONCAKE_MEM_POOL:-}"

# Core runtime knobs.
export DTYPE="${DTYPE:-bfloat16}"
export CONTEXT_LENGTH="${CONTEXT_LENGTH:-32768}"
export PREFILL_MEM_FRACTION_STATIC="${PREFILL_MEM_FRACTION_STATIC:-0.78}"
export DECODE_MEM_FRACTION_STATIC="${DECODE_MEM_FRACTION_STATIC:-0.86}"
export DECODE_MAX_RUNNING_REQUESTS="${DECODE_MAX_RUNNING_REQUESTS:-128}"

# Router policies and readiness.
export SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT="${SGLANG_DISAGGREGATION_BOOTSTRAP_TIMEOUT:-600}"
export SGLANG_DISAGGREGATION_WAITING_TIMEOUT="${SGLANG_DISAGGREGATION_WAITING_TIMEOUT:-600}"
export ROUTER_WORKER_STARTUP_TIMEOUT_SECS="${ROUTER_WORKER_STARTUP_TIMEOUT_SECS:-1800}"
export PREFILL_POLICY="${PREFILL_POLICY:-cache_aware}"
export DECODE_POLICY="${DECODE_POLICY:-power_of_two}"
export WAIT_FOR_READY="${WAIT_FOR_READY:-1}"
export READY_TIMEOUT_SECS="${READY_TIMEOUT_SECS:-1800}"

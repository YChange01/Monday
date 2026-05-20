# AI Infra Interview Training

This repository is an AI infrastructure interview training workspace focused on
hands-on systems practice, especially LLM serving, disaggregated inference, and
performance benchmarking.

## Repository Layout

- `pd_disagg/`: SGLang prefill/decode disaggregation launch, smoke test, and
  benchmark scripts for Qwen3-32B on B200.

## Current Focus

- Understand SGLang serving architecture.
- Practice prefill/decode disaggregation bring-up.
- Build repeatable smoke tests and serving benchmarks.
- Collect tuning observations for AI Infra interview discussions.

## Getting Started

```bash
cd pd_disagg
./start_pd.sh
```

Install `sglang`, `sglang-router`, and `mooncake-transfer-engine` in your Python
environment before launching. Runtime defaults live in
`start_pd.sh`; create `env.b200.local.sh` only when the target machine
needs overrides such as GPU groups, ports, model path, or Python path.

# AI Infra Interview Training

This repository is an AI infrastructure interview training workspace focused on
hands-on systems practice, especially LLM serving, disaggregated inference, and
performance benchmarking.

## Repository Layout

- `pd_disagg/`: SGLang prefill/decode disaggregation launch, setup, smoke test,
  and benchmark scripts for Qwen3-32B on B200.
- `sglang/`: upstream SGLang source tracked as a Git submodule and pinned to the
  commit used by the local training scripts.

## Current Focus

- Understand SGLang serving architecture.
- Practice prefill/decode disaggregation bring-up.
- Build repeatable smoke tests and serving benchmarks.
- Collect tuning observations for AI Infra interview discussions.

## Getting Started

```bash
git submodule update --init --recursive
cd pd_disagg
cp env.b200.example.sh env.b200.local.sh
```

Edit `env.b200.local.sh` for the target machine before running setup or launch
scripts.

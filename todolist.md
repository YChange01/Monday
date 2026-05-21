# PD 分离测试 TODO

## 当前默认配置

- [ ] 模型路径：`/mnt/nvme3n1/g00872988/models/Qwen3-32B`
- [ ] 默认拓扑：`PREFILL_GROUPS="0;1"`，`DECODE_GROUPS="2;3"`
- [ ] 默认 transfer backend：`TRANSFER_BACKEND=nixl`
- [ ] 默认 benchmark 数据集：`BENCH_DATASET_NAME=random-ids`，避免访问 Hugging Face

## 1. 基础连通性与稳定性

- [ ] 启动服务：

```bash
cd /mnt/nvme3n1/g00872988/Monday/pd_disagg
bash stop_pd.sh
bash start_pd.sh
```

- [ ] 确认启动输出包含：

```text
PD generation is ready.
```

- [ ] 跑短 smoke：

```bash
bash smoke_test.sh
```

- [ ] 跑中文 smoke：

```bash
SMOKE_TEXT="介绍一下长城" SMOKE_MAX_NEW_TOKENS=128 bash smoke_test.sh
```

观察指标：

- [ ] 无 500/503/504
- [ ] `/generate` 能返回正常 JSON
- [ ] `logs/prefill_*.log`、`logs/decode_*.log` 无 transfer failed

## 2. 基础稳定性 sweep

```bash
SWEEP_REQUEST_RATES="10 20 40" \
SWEEP_WORKLOADS="512:64 2048:256" \
SWEEP_NUM_PROMPTS=1000 \
SWEEP_MAX_CONCURRENCY=128 \
bash sweep_bench.sh
```

重点看：

- [ ] `Successful requests`
- [ ] `P99 TTFT`
- [ ] `P99 TPOT`
- [ ] `Max ITL`
- [ ] router/prefill/decode 日志是否有 500/504/transfer failed

## 3. 容量上限扫描

```bash
SWEEP_REQUEST_RATES="10 20 40 80 120 160" \
SWEEP_WORKLOADS="2048:256" \
SWEEP_NUM_PROMPTS=1000 \
SWEEP_MAX_CONCURRENCY=256 \
bash sweep_bench.sh
```

判断瓶颈：

- [ ] `Request throughput` 跟不上 `Traffic request rate`：系统接近上限
- [ ] `TTFT` 飙升：prefill 或排队瓶颈
- [ ] `TPOT` 飙升：decode 瓶颈
- [ ] `Output tok/s` 不再增长：decode 吞吐到顶

## 4. 长上下文测试

推荐直接跑封装脚本：

```bash
bash long_context_bench.sh
```

快速验证一轮：

```bash
LONG_CONTEXT_QUICK=1 bash long_context_bench.sh
```

等价的手动 sweep：

```bash
SWEEP_REQUEST_RATES="2 5 10 20" \
SWEEP_WORKLOADS="4096:256 8192:256 16384:256" \
SWEEP_NUM_PROMPTS=200 \
SWEEP_MAX_CONCURRENCY=64 \
bash sweep_bench.sh
```

重点看：

- [ ] `Input token throughput`
- [ ] `Mean TTFT`
- [ ] `P99 TTFT`
- [ ] GPU 显存余量
- [ ] prefill queue 是否堆积

## 5. Decode 压力测试

```bash
SWEEP_REQUEST_RATES="5 10 20 40" \
SWEEP_WORKLOADS="512:512 512:1024" \
SWEEP_NUM_PROMPTS=300 \
SWEEP_MAX_CONCURRENCY=128 \
bash sweep_bench.sh
```

重点看：

- [ ] `Output token throughput`
- [ ] `Mean TPOT`
- [ ] `P99 TPOT`
- [ ] `ITL`
- [ ] decode GPU 利用率

## 6. 拓扑对比

多副本拓扑：

```bash
PREFILL_GROUPS="0;1" DECODE_GROUPS="2;3" bash start_pd.sh
```

TP=2 拓扑：

```bash
PREFILL_GROUPS="0,1" DECODE_GROUPS="2,3" bash start_pd.sh
```

对每种拓扑跑同一套 sweep，比较：

- [ ] `req/s`
- [ ] `input tok/s`
- [ ] `output tok/s`
- [ ] `P99 TTFT`
- [ ] `P99 TPOT`
- [ ] 显存余量
- [ ] 失败率

## 7. Prefill/Decode 配比测试

8 卡场景可尝试：

```bash
PREFILL_GROUPS="0;1;2" DECODE_GROUPS="3;4;5;6;7" bash start_pd.sh
PREFILL_GROUPS="0;1;2;3;4" DECODE_GROUPS="5;6;7" bash start_pd.sh
```

判断依据：

- [ ] TTFT 高：prefill 不够
- [ ] TPOT 高：decode 不够
- [ ] 两者都高：总负载过高或 transfer 有瓶颈

## 8. 路由策略测试

当前默认：

```bash
PREFILL_POLICY=cache_aware
DECODE_POLICY=round_robin
```

对比：

```bash
PREFILL_POLICY=round_robin bash start_pd.sh
PREFILL_POLICY=cache_aware bash start_pd.sh
```

重点测试：

- [ ] shared prefix
- [ ] 多轮对话
- [ ] 长上下文
- [ ] cache-aware 是否降低 TTFT

## 9. 故障恢复测试

运行 benchmark 时查看 PID：

```bash
cat run/pd_qwen3_32b.pid
```

杀掉一个 worker：

```bash
kill <pid>
```

观察：

- [ ] 请求是否部分失败
- [ ] router 是否摘除坏 worker
- [ ] 剩余 worker 是否继续处理
- [ ] 恢复后是否需要重启整套服务

## 10. OpenAI API 兼容测试

```bash
SMOKE_MODE=chat \
SMOKE_TEXT="介绍一下长城" \
SMOKE_MAX_NEW_TOKENS=128 \
bash smoke_test.sh
```

观察：

- [ ] `/v1/chat/completions` 是否成功
- [ ] 返回格式是否兼容 OpenAI client

## 11. 资源监控

跑 sweep 时另开终端：

```bash
nvidia-smi dmon -s pucm
```

观察：

- [ ] prefill 卡 GPU 利用率
- [ ] decode 卡 GPU 利用率
- [ ] 显存余量
- [ ] 是否某一边明显闲置

## 12. 推荐下一组综合测试

```bash
SWEEP_REQUEST_RATES="10 20 40 80 120" \
SWEEP_WORKLOADS="512:64 2048:256 8192:256 512:1024" \
SWEEP_NUM_PROMPTS=500 \
SWEEP_MAX_CONCURRENCY=256 \
bash sweep_bench.sh
```

目标：

- [ ] 短请求场景
- [ ] 标准请求场景
- [ ] 长 prompt 场景
- [ ] 长输出场景
- [ ] 判断 PD 瓶颈在 prefill、decode、transfer 还是 router

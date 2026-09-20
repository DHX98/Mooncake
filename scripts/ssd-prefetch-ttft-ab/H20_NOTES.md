# H20 测试环境说明（PLATFORM=h20）

`PLATFORM=h20 . ./env.sh` 即可把整套 A/B harness 切到 NVIDIA H20。
方法学不变（fill → overflow → settle → measure，CONC 可调）。

## 跑之前必须确认的 4 件事

| 项 | 位置 | 说明 |
|---|---|---|
| **模型权重** | `MODEL`（env.sh 或环境变量） | `/data/DeepSeek-V4-Flash-w8a8-mtp` 是 **Ascend 专用 w8a8 量化**，H20 不能用。需要 NVIDIA 构建（FP8/BF16），并在 `platforms/h20.env` 的 `VLLM_EXTRA_ARGS` 里补量化/分词器参数 |
| **connector 名** | `platforms/h20.env` 的 `KV_JSON` | 默认 `MooncakeStoreConnector`（vLLM upstream 文档口径）。**用你部署的 vLLM 版本实际存在的 connector 名核对**：`python -c "import vllm; print(vllm.__version__)"` 后查 `vllm/distributed/kv_transfer/kv_connector/` 下的实现 |
| **网络** | `MOONCAKE_PROTOCOL` / `SOCKET_IFNAME` / `NCCL_*` | 默认全 TCP（mooncake protocol=tcp、NCCL_IB_DISABLE=1），开箱即用。要 RDMA 再改 `MOONCAKE_PROTOCOL=rdma` + `MOONCAKE_DEVICE_NAME=<nic>` + 放开 NCCL_IB |
| **TP 数** | `TP_SIZE`（默认 8） | H20 是 96GB HBM3；DSv4-Flash 若单机放不下就调 TP_SIZE |

## 与 A2 版本的差异点（为什么能直接用）

- env.sh 顶部 `PLATFORM` 开关（默认 ascend 保持向后兼容）；
- `mooncake_a/b.json` 不再提交静态文件——env.sh 每次 source 时从
  `mooncake.json.tmpl` 按本机 protocol/路径/尺寸生成；
- serve.sh 的平台相关段（可见卡、HCCL/NCCL、connector、量化参数）
  全部来自 `platforms/$PLATFORM.env`。

## 两个方法论注意事项

1. **16K 命中粒度是 A2 connector 的实测值**。NVIDIA connector 的缓存
   块粒度可能不同——`PREFIX_TOKENS` 别照抄 16385。先跑 fill 后用
   SSD-only 前置检查（`batch_get_replica_desc` 抽查）确认命中最小粒度，
   不够就加大 PREFIX_TOKENS，**不够命中粒度时实验直接无效**。
2. H20 的 KV 也是 GPU 显存侧搬运，Mooncake store 的 DRAM/SSD 行为与
   A2 一致，TTFT 收益的构成（排队窗口藏 SSD 读）不变，数字量级可能
   不同，以实测为准。

## 提交证据前

照 `FINAL_ROUND.md` 铁律：先 `bash scrub.sh <文件>` 再 `git add`。
